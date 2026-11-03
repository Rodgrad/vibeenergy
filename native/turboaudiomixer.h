#pragma once
#include <QObject>
#include <QIODevice>
#include <QAudioFormat>
#include <QAudioSink>
#include <QMutex>
#include <QTimer>
#include <QUrl>
#include <array>
#include <vector>

// An unbuffered PCM source. Four voices are mixed into one hardware stream.
class TurboPcmSource : public QIODevice {
public:
    explicit TurboPcmSource(QObject *parent=nullptr);
    bool load(const QString &directory);
    void setFormat(const QAudioFormat &format);
    void boost();
    void strike();
    void powerOff();
    void silence();
    int powerOffMilliseconds() const;
    bool isSequential() const override { return true; }
    qint64 bytesAvailable() const override { return 65536+QIODevice::bytesAvailable(); }
protected:
    qint64 readData(char *data,qint64 length) override;
    qint64 writeData(const char *,qint64) override { return -1; }
private:
    mutable QMutex m_mutex;
    std::array<std::vector<float>,4> m_clips;
    std::array<double,4> m_positions{{-1,-1,-1,-1}};
    QAudioFormat m_format;
};

class TurboAudioMixer : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl sourceDirectory READ sourceDirectory WRITE setSourceDirectory NOTIFY readyChanged)
    Q_PROPERTY(qreal level READ level WRITE setLevel NOTIFY levelChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool finishing READ finishing NOTIFY finishingChanged)
    Q_PROPERTY(bool outputActive READ outputActive NOTIFY outputActiveChanged)
    Q_PROPERTY(int strikeCount READ strikeCount NOTIFY strikeCountChanged)
public:
    explicit TurboAudioMixer(QObject *parent=nullptr);
    ~TurboAudioMixer() override;
    QUrl sourceDirectory() const { return m_directory; }
    void setSourceDirectory(const QUrl &url);
    qreal level() const { return m_level; }
    void setLevel(qreal value);
    bool ready() const { return m_ready; }
    bool finishing() const { return m_finishing; }
    int strikeCount() const { return m_strikeCount; }
    bool outputActive() const { return m_sink!=nullptr; }
    int outputGeneration() const { return m_outputGeneration; }
    Q_INVOKABLE void resumeBoost();
    Q_INVOKABLE void playStrike();
    Q_INVOKABLE void playPowerOff();
    Q_INVOKABLE void stopAll();
signals:
    void outputActiveChanged();
    void readyChanged();
    void levelChanged();
    void finishingChanged();
    void strikeCountChanged();
private:
    bool ensureOutput();
    TurboPcmSource m_pcm;
    QAudioSink *m_sink=nullptr;
    QTimer m_finishTimer;
    QUrl m_directory;
    qreal m_level=.10;
    bool m_ready=false,m_finishing=false;
    int m_strikeCount=0,m_outputGeneration=0;
};
