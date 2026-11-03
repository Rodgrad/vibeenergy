#include "turboaudiomixer.h"
#include <QAudioDevice>
#include <QMediaDevices>
#include <QFile>
#include <QDir>
#include <QMutexLocker>
#include <QtEndian>
#include <QDebug>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace {
std::vector<float> readWave(const QString &path) {
    QFile file(path);
    if(!file.open(QIODevice::ReadOnly) || file.size()>16*1024*1024)return {};
    const QByteArray bytes=file.readAll();
    if(bytes.size()<12 || bytes.mid(0,4)!="RIFF" || bytes.mid(8,4)!="WAVE")return {};
    bool pcm=false;QByteArray samples;
    for(qsizetype offset=12;offset+8<=bytes.size();) {
        const quint32 size=qFromLittleEndian<quint32>(bytes.constData()+offset+4);
        if(quint64(offset)+8+size>quint64(bytes.size()))return {};
        const char *chunk=bytes.constData()+offset+8;
        if(bytes.mid(offset,4)=="fmt " && size>=16)
            pcm=qFromLittleEndian<quint16>(chunk)==1 && qFromLittleEndian<quint16>(chunk+2)==2 &&
                qFromLittleEndian<quint32>(chunk+4)==48000 && qFromLittleEndian<quint16>(chunk+14)==16;
        if(bytes.mid(offset,4)=="data")samples=bytes.mid(offset+8,size);
        offset+=8+qsizetype(size)+(size%2);
    }
    if(!pcm || samples.isEmpty() || samples.size()%4)return {};
    std::vector<float> result(samples.size()/2);
    for(size_t i=0;i<result.size();++i)result[i]=qFromLittleEndian<qint16>(samples.constData()+i*2)/32768.f;
    return result;
}
}
TurboPcmSource::TurboPcmSource(QObject *parent):QIODevice(parent) { open(QIODevice::ReadOnly|QIODevice::Unbuffered); }
bool TurboPcmSource::load(const QString &directory) {
    QMutexLocker lock(&m_mutex);
    const std::array<QString,4> names{{"electricity-loop.wav","power_on.wav","zap.wav","poweroff.wav"}};
    for(size_t i=0;i<names.size();++i)m_clips[i]=readWave(QDir(directory).filePath(names[i]));
    m_positions.fill(-1);
    return std::all_of(m_clips.begin(),m_clips.end(),[](const auto &clip){return !clip.empty();});
}
void TurboPcmSource::setFormat(const QAudioFormat &format) { QMutexLocker lock(&m_mutex);m_format=format; }
void TurboPcmSource::boost() { QMutexLocker lock(&m_mutex);m_positions={{0,0,-1,-1}}; }
void TurboPcmSource::strike() { QMutexLocker lock(&m_mutex);m_positions[2]=0; }
void TurboPcmSource::powerOff() { QMutexLocker lock(&m_mutex);m_positions={{-1,-1,-1,0}}; }
void TurboPcmSource::silence() { QMutexLocker lock(&m_mutex);m_positions.fill(-1); }
int TurboPcmSource::powerOffMilliseconds() const { QMutexLocker lock(&m_mutex);return int(m_clips[3].size()/2*1000/48000); }
qint64 TurboPcmSource::readData(char *data,qint64 length) {
    QMutexLocker lock(&m_mutex);
    std::memset(data,0,size_t(length));
    if(!m_format.isValid() || m_format.bytesPerFrame()<=0)return length;
    const qint64 frames=length/m_format.bytesPerFrame();
    const double step=48000./m_format.sampleRate();
    char *out=data;
    for(qint64 frame=0;frame<frames;++frame) {
        float stereo[2]={0,0};
        for(size_t voice=0;voice<m_clips.size();++voice) {
            auto &position=m_positions[voice];const auto &clip=m_clips[voice];
            const size_t count=clip.size()/2;
            if(position<0 || count==0)continue;
            if(position>=double(count)) {
                if(voice==0)position=std::fmod(position,double(count));
                else {position=-1;continue;}
            }
            const size_t index=size_t(position),next=voice==0?(index+1)%count:std::min(index+1,count-1);
            const float fraction=float(position-index),gain=voice==0?12.f/35.f:1.f;
            for(int channel=0;channel<2;++channel)
                stereo[channel]+=(clip[index*2+channel]*(1-fraction)+clip[next*2+channel]*fraction)*gain;
            position+=step;
        }
        for(int channel=0;channel<m_format.channelCount();++channel) {
            const float value=std::clamp(m_format.channelCount()==1?(stereo[0]+stereo[1])*.5f:stereo[channel%2],-1.f,1.f);
            switch(m_format.sampleFormat()) {
            case QAudioFormat::Float: std::memcpy(out,&value,4);out+=4;break;
            case QAudioFormat::Int16: {qint16 sample=qint16(value*32767);std::memcpy(out,&sample,2);out+=2;break;}
            case QAudioFormat::Int32: {qint32 sample=qint32(double(value)*2147483647.);std::memcpy(out,&sample,4);out+=4;break;}
            case QAudioFormat::UInt8: *out++=char(std::clamp(int(value*127+128),0,255));break;
            default: return length;
            }
        }
    }
    return length;
}
TurboAudioMixer::TurboAudioMixer(QObject *parent):QObject(parent) {
    m_finishTimer.setSingleShot(true);
    connect(&m_finishTimer,&QTimer::timeout,this,&TurboAudioMixer::stopAll);
}
TurboAudioMixer::~TurboAudioMixer() { m_finishTimer.stop();if(m_sink){m_sink->disconnect(this);m_sink->reset();delete m_sink;} }
void TurboAudioMixer::setSourceDirectory(const QUrl &url) {
    if(url==m_directory)return;
    stopAll();m_directory=url;m_ready=m_pcm.load(url.toLocalFile());emit readyChanged();
}
void TurboAudioMixer::setLevel(qreal value) {
    value=std::clamp(value,0.,1.);if(qFuzzyCompare(value+1,m_level+1))return;
    m_level=value;if(m_sink)m_sink->setVolume(value);emit levelChanged();
}
bool TurboAudioMixer::ensureOutput() {
    if(m_sink)return true;
    if(!m_ready)return false;
    const auto device=QMediaDevices::defaultAudioOutput();
    if(device.isNull())return false;
    QAudioFormat format;format.setSampleRate(48000);format.setChannelCount(2);format.setSampleFormat(QAudioFormat::Int16);
    if(!device.isFormatSupported(format))format=device.preferredFormat();
    if(!format.isValid())return false;
    m_pcm.setFormat(format);
    m_sink=new QAudioSink(device,format,this);
    m_sink->setObjectName("vibeenergyTurboAudioSink");
    m_sink->setBufferSize(format.bytesForDuration(40000));
    m_sink->setVolume(m_level);
    connect(m_sink,&QAudioSink::stateChanged,this,[this]{
        if(m_sink && m_sink->state()==QAudio::StoppedState && m_sink->error()!=QAudio::NoError) QTimer::singleShot(0,this,&TurboAudioMixer::stopAll);
    });
    ++m_outputGeneration;
    m_sink->start(&m_pcm);
    emit outputActiveChanged();
    return true;
}
void TurboAudioMixer::resumeBoost() {
    m_finishTimer.stop();m_pcm.boost();
    if(m_finishing){m_finishing=false;emit finishingChanged();}
    ensureOutput();
}
void TurboAudioMixer::playStrike() {
    if(!m_sink || m_finishing)return;
    m_pcm.strike();++m_strikeCount;emit strikeCountChanged();
}
void TurboAudioMixer::playPowerOff() {
    if(!m_sink)return;
    m_pcm.powerOff();m_finishing=true;emit finishingChanged();
    m_finishTimer.start(m_pcm.powerOffMilliseconds()+100);
}
void TurboAudioMixer::stopAll() {
    m_finishTimer.stop();
    if(m_sink) {auto *sink=m_sink;m_sink=nullptr;sink->disconnect(this);sink->reset();delete sink;emit outputActiveChanged();}
    m_pcm.silence();
    if(m_finishing){m_finishing=false;emit finishingChanged();}
}
