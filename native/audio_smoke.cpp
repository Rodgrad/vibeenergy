#include "turboaudiomixer.h"
#include <QGuiApplication>
#include <QAudioDevice>
#include <QMediaDevices>
#include <QTimer>
#include <iostream>
#include <cstring>
#include <cmath>

int main(int argc,char **argv) {
    QGuiApplication app(argc,argv);
    app.setApplicationName("VibeEnergy audio test");
    if(argc!=2)return 2;
    TurboPcmSource pcm;
    if(!pcm.load(QString::fromLocal8Bit(argv[1]))) {std::cerr<<"PCM samples failed to load\n";return 1;}
    QAudioFormat format;format.setSampleRate(48000);format.setChannelCount(2);format.setSampleFormat(QAudioFormat::Float);
    pcm.setFormat(format);pcm.boost();const auto baseline=pcm.read(262144);
    pcm.boost();pcm.strike();const auto mixed=pcm.read(262144);
    int different=0;
    for(qsizetype i=0;i+4<=mixed.size();i+=4) {
        float a,b;std::memcpy(&a,baseline.constData()+i,4);std::memcpy(&b,mixed.constData()+i,4);
        if(!std::isfinite(b) || std::abs(b)>1)return 1;
        if(std::abs(a-b)>.0001)++different;
    }
    if(different<100) {std::cerr<<"Zap was not mixed over buzz and activation\n";return 1;}
    pcm.silence();const auto silent=pcm.read(4096);
    for(char byte:silent)if(byte!=0)return 1;
    std::cout<<"PCM voices overlap, remain clipped safely, and stop to silence\n";
    if(QMediaDevices::defaultAudioOutput().isNull()) {std::cout<<"Audio device unavailable\n";return 77;}
    TurboAudioMixer mixer;
    mixer.setSourceDirectory(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])+"/"));
    mixer.setLevel(0);
    mixer.resumeBoost();
    if(!mixer.outputActive() || mixer.outputGeneration()!=1)return 1;
    TurboAudioMixer second;
    const bool dual=qEnvironmentVariableIsSet("ENERGYTLK_AUDIO_SMOKE_DUAL");
    if(dual) {
        second.setSourceDirectory(mixer.sourceDirectory());second.setLevel(0);second.resumeBoost();
        if(!second.outputActive())return 1;
    }
    int result=0;
    QTimer::singleShot(100,&app,[&]{mixer.playStrike();});
    QTimer::singleShot(200,&app,[&]{mixer.playStrike();if(dual)second.playStrike();});
    QTimer::singleShot(350,&app,[&]{
        mixer.resumeBoost();
        if(!mixer.outputActive() || mixer.outputGeneration()!=1 || mixer.strikeCount()!=2)result=1;
    });
    QTimer::singleShot(450,&app,[&]{mixer.playPowerOff();if(!mixer.finishing())result=1;});
    QTimer::singleShot(2100,&app,[&]{
        if(mixer.outputActive() || mixer.finishing())result=1;
        else std::cout<<"One output retained through overlapping effects; released after power-off\n";
        if(dual) {
            if(!second.outputActive() || second.outputGeneration()!=1 || second.strikeCount()!=1)result=1;
            else std::cout<<"Second window audio stayed active after first window stopped\n";
            second.stopAll();
        }
        mixer.resumeBoost();if(mixer.outputGeneration()!=2)result=1;
        mixer.stopAll();
        if(mixer.outputActive())result=1;
        else std::cout<<"Immediate sound-disable shutdown verified\n";
        app.exit(result);
    });
    return app.exec();
}
