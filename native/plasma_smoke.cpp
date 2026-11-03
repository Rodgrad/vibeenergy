#include <QGuiApplication>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QImage>
#include <QTimer>
#include <iostream>
#include "plasmafield.h"

// Real scene-graph regression test: dense edge ribbons must not drop later bolts.
int main(int argc,char **argv) {
    QGuiApplication app(argc,argv);
    QQuickWindow window;window.resize(1200,800);window.setColor(QColor("#171c23"));
    auto *field=new PlasmaField(window.contentItem());
    field->setSize(QSizeF(1200,800));field->setFrame(QRectF(32,32,1136,736));
    // Keep the decorative button corona outside the sampled interior region.
    field->setOrigin(QPointF(1700,400));field->setIntensity(1);field->setContinuous(true);
    field->setTime(1.0);window.show();
    int captures=0,brightest=0;
    QTimer timer;timer.setInterval(250);
    QObject::connect(&timer,&QTimer::timeout,&app,[&]{
        const auto api=window.rendererInterface()->graphicsApi();
        if(api==QSGRendererInterface::Software || api==QSGRendererInterface::Null || api==QSGRendererInterface::Unknown) {
            std::cout<<"GPU renderer unavailable; lightning pixel check skipped\n";app.exit(77);return;
        }
        const QImage frame=window.grabWindow();
        if(frame.isNull()){std::cerr<<"Cannot capture GPU frame\n";app.exit(1);return;}
        const qreal scale=frame.devicePixelRatio();int count=0;
        for(int y=int(80*scale);y<qMin(frame.height(),int(720*scale));++y)
            for(int x=int(120*scale);x<qMin(frame.width(),int(960*scale));++x) {
                const QColor pixel=frame.pixelColor(x,y);
                if(pixel.blue()>160 && pixel.green()>110)++count;
            }
        brightest=qMax(brightest,count);
        if(++captures==3) {
            std::cout<<"Bright lightning pixels inside frame: "<<brightest<<'\n';
            app.exit(brightest>100?0:1);return;
        }
        field->setTime(1.0+captures*.15);
    });
    timer.start();QTimer::singleShot(10000,&app,[&]{app.exit(1);});
    return app.exec();
}
