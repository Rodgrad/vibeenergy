#include "plasmafield.h"
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <QRandomGenerator>
#include <algorithm>
#include <cmath>
#include <vector>

PlasmaField::PlasmaField(QQuickItem *parent):QQuickItem(parent) { setFlag(ItemHasContents,true); setAcceptedMouseButtons(Qt::NoButton); }
#define SETTER(method,type,field) void PlasmaField::method(type v) { if(field==v)return; field=v; emit appearanceChanged(); update(); }
SETTER(setTime,qreal,m_time)
SETTER(setIntensity,qreal,m_intensity)
SETTER(setFrame,QRectF,m_frame)
SETTER(setOrigin,QPointF,m_origin)
SETTER(setBackgroundLayer,bool,m_background)
SETTER(setReducedMotion,bool,m_reduced)
SETTER(setContinuous,bool,m_continuous)
SETTER(setBorderOnly,bool,m_borderOnly)
#undef SETTER

QSGNode *PlasmaField::updatePaintNode(QSGNode *old,UpdatePaintNodeData *) {
    struct PlasmaNode : QSGGeometryNode { std::vector<QSGGeometry::ColoredPoint2D> vertices; std::vector<double> light; std::vector<QPointF> strike; std::vector<QPointF> sparks; std::vector<std::vector<QPointF>> branches; std::vector<std::vector<QPointF>> interior; std::vector<bool> interiorHits; int interiorSlot=-1, interiorSoundSlot=-1; int strikeSlot=-1, soundSlot=-1; double strikeDelay=0, strikeDuration=.35; };
    auto *node=static_cast<PlasmaNode *>(old);
    if(!node) {
        node=new PlasmaNode;
        auto *g=new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(),0);
        g->setDrawingMode(QSGGeometry::DrawTriangles); g->setVertexDataPattern(QSGGeometry::DynamicPattern);
        node->setGeometry(g); node->setFlag(QSGNode::OwnsGeometry);
        auto *material=new QSGVertexColorMaterial;
        // Dense plasma geometry exceeds the batcher's 16-bit merged-index range.
        // Keep this node as a direct draw so later lightning vertices are preserved.
        material->setFlag(QSGMaterial::NoBatching,true);
        node->setMaterial(material); node->setFlag(QSGNode::OwnsMaterial);
    }
    using V=QSGGeometry::ColoredPoint2D;
    auto &vertices=node->vertices; vertices.clear(); if(vertices.capacity()<32000)vertices.reserve(32000);
    const double t=m_reduced?0:m_time, strength=std::clamp(double(m_intensity),0.,1.);
    auto vertex=[&](QPointF p,double a,bool white) {
        a=std::clamp(a*strength,0.,.8); V v;
        v.set(p.x(),p.y(),uchar((white?235:0)*a),uchar((white || m_borderOnly?255:170)*a),uchar((m_borderOnly?(white?210:100):255)*a),uchar(255*a));
        vertices.push_back(v);
    };
    auto &flowLight=node->light;
    bool flowing=false;
    double flowPhase=0;
    auto envelope=[&](double u) {
        if(!flowing)return 1.;
        auto periodic=[](double d){return std::atan2(std::sin(d*6.2831853),std::cos(d*6.2831853))/6.2831853;};
        double head=periodic(u-flowPhase),tail=periodic(u-flowPhase+.11);
        return .045+.72*std::exp(-head*head/.004)+.26*std::exp(-tail*tail/.033);
    };
    auto strip=[&](const std::vector<QPointF> &p,double width,double alpha,bool white=false) {
        for(size_t i=1;i<p.size();++i) {
            QPointF d=p[i]-p[i-1]; double length=std::hypot(d.x(),d.y());if(length<.001)continue;
            double light=flowing && flowLight.size()==p.size() ? flowLight[i] : 1.;
            double thickness=flowing ? .6+.5*light : 1.;
            QPointF n(-d.y()/length*width*thickness/2,d.x()/length*width*thickness/2);
            vertex(p[i-1]+n,alpha*light,white); vertex(p[i-1]-n,alpha*light,white); vertex(p[i]+n,alpha*light,white);
            vertex(p[i]+n,alpha*light,white); vertex(p[i-1]-n,alpha*light,white); vertex(p[i]-n,alpha*light,white);
        }
    };
    auto softGlow=[&](const std::vector<QPointF> &p,double width,double alpha) {
        for(size_t i=1;i<p.size();++i) {
            QPointF d=p[i]-p[i-1];double length=std::hypot(d.x(),d.y());if(length<.001)continue;
            double light=flowing && flowLight.size()==p.size() ? flowLight[i] : 1.;
            double thickness=flowing ? .6+.5*light : 1.;
            QPointF n(-d.y()/length*width*thickness/2,d.x()/length*width*thickness/2);
            for(int sign:{-1,1}) {
                QPointF side=n*sign;
                vertex(p[i-1],alpha*light,false);vertex(p[i-1]+side,0,false);vertex(p[i],alpha*light,false);
                vertex(p[i],alpha*light,false);vertex(p[i-1]+side,0,false);vertex(p[i]+side,0,false);
            }
        }
    };
    auto lightning=[&](const std::vector<QPointF> &path,double age,double duration,double scale) {
        if(path.size()<2 || age<0 || age>duration+.4)return;
        double reveal=std::clamp(age/.09,0.,1.);
        double light=age<.09 ? .8 : age<duration ? .55+.45*std::exp(-(age-.09)*16) : .18*std::pow(1-(age-duration)/.4,2);
        std::vector<QPointF> visible;
        double end=reveal*(path.size()-1);size_t whole=size_t(end);
        for(size_t j=0;j<=whole && j<path.size();++j)visible.push_back(path[j]);
        if(whole+1<path.size())visible.push_back(path[whole]+(path[whole+1]-path[whole])*(end-whole));
        softGlow(visible,85,light*scale*.10);softGlow(visible,34,light*scale*.28);
        strip(visible,5,light*scale*.6);strip(visible,2.1,light*scale*.85);
        // White-hot center over a cyan sheath; the blue afterimage outlives the core.
        if(age<duration)strip(visible,.9,light*scale,true);
    };
    auto ribbon=[&](const std::vector<QPointF> &p,double alpha) {
        if(flowing) {
            flowLight.resize(p.size());
            for(size_t i=0;i<p.size();++i)flowLight[i]=envelope(double(i)/(p.size()-1));
        }
        softGlow(p,55,alpha*.055);softGlow(p,24,alpha*.2);strip(p,4,alpha*.3);strip(p,1.3,alpha*.75);strip(p,.6,alpha*.8,true);
    };
    QRectF f=m_frame.isValid()?m_frame:QRectF(0,0,width(),height());
    if(m_background) {
        if(!m_reduced)for(int k=0;k<3;++k) {
            std::vector<QPointF> path;
            for(int i=0;i<=120;++i) {
                double u=i/120.;
                double y=f.top()+(k==0?.085:k==1?.45:.91)*f.height()+std::sin(u*7+t*.9+k)*26+std::sin(u*13-t*.6)*8;
                path.emplace_back(f.left()+u*f.width(),y);
            }
            flowing=true;flowPhase=std::fmod(t*.14+k*.32,1.);
            ribbon(path,k==0?.85:.35);flowing=false;
        }
    } else {
        if(!m_reduced) {
            // A single rounded path lets bright plasma cores advect continuously
            // through corners, rather than oscillating as four disconnected wires.
            const double radius=m_borderOnly?14:24, horizontal=std::max(1.,f.width()-2*radius),vertical=std::max(1.,f.height()-2*radius);
            const double arc=1.5707963268*radius,perimeter=2*(horizontal+vertical)+4*arc;
            auto boundary=[&](double u) {
                double d=std::fmod(u+1.,1.)*perimeter;
                if(d<horizontal)return QPointF(f.left()+radius+d,f.top());d-=horizontal;
                if(d<arc){double a=-1.5707963268+d/radius;return QPointF(f.right()-radius+std::cos(a)*radius,f.top()+radius+std::sin(a)*radius);}d-=arc;
                if(d<vertical)return QPointF(f.right(),f.top()+radius+d);d-=vertical;
                if(d<arc){double a=d/radius;return QPointF(f.right()-radius+std::cos(a)*radius,f.bottom()-radius+std::sin(a)*radius);}d-=arc;
                if(d<horizontal)return QPointF(f.right()-radius-d,f.bottom());d-=horizontal;
                if(d<arc){double a=1.5707963268+d/radius;return QPointF(f.left()+radius+std::cos(a)*radius,f.bottom()-radius+std::sin(a)*radius);}d-=arc;
                if(d<vertical)return QPointF(f.left(),f.bottom()-radius-d);d-=vertical;
                double a=3.1415926536+d/radius;return QPointF(f.left()+radius+std::cos(a)*radius,f.top()+radius+std::sin(a)*radius);
            };
            const double originPhase=(horizontal+arc+std::clamp(m_origin.y()-f.top()-radius,0.,vertical))/perimeter;
            for(int k=0;k<2;++k) {
                std::vector<QPointF> path;path.reserve(421);
                for(int i=0;i<=420;++i) {
                    double u=i/420.;QPointF p=boundary(u),delta=boundary(u+.0001)-p;
                    double length=std::max(.001,std::hypot(delta.x(),delta.y()));
                    QPointF outward(delta.y()/length,-delta.x()/length);
                    double swell=-2+k*5+std::sin(u*18.8495559-t*.85+k)*6+std::sin(u*43.982297+t*.55)*2;
                    path.push_back(p+outward*(m_borderOnly?-1+k*5+swell*1.5:swell));
                }
                flowing=true;flowPhase=std::fmod(originPhase+t*(k==0?.18:-.13)+k*.42+2.,1.);
                ribbon(path,k==0?1.:.65);
                if(m_borderOnly){softGlow(path,30,k==0?.5:.35);strip(path,3,k==0?1.:.8,true);}
                else {
                    // Bright travelling cyan sheath and pale core follow the existing envelope.
                    softGlow(path,38,k==0?.27:.17);
                    strip(path,2.8,k==0?.8:.55);
                    strip(path,1.1,k==0?.95:.65,true);
                }
                flowing=false;
            }
            if(!m_borderOnly) {
            // Swirling corona emerges from the button, with a single ignition wave.
            for(int k=0;k<3;++k) {
                std::vector<QPointF> path;
                for(int i=0;i<=100;++i) {
                    double a=i/100.*6.2831853;
                    double r=1+.12*std::sin(a*2-t*1.5+k)+.05*std::sin(a*5+t*.7);
                    path.emplace_back(m_origin.x()+std::cos(a)*(100+k*15)*r,m_origin.y()+std::sin(a)*(45+k*11)*r);
                }
                flowing=true;flowPhase=std::fmod(t*.28+k*.31,1.);
                ribbon(path,.85-k*.15);flowing=false;
            }
            if(t<1) {
                std::vector<QPointF> path;
                for(int i=0;i<=100;++i){double a=i/100.*6.2831853;path.emplace_back(m_origin.x()+std::cos(a)*t*f.width(),m_origin.y()+std::sin(a)*t*f.height());}
                ribbon(path,(1-t)*.7);
            }
            if(std::fmod(t,1.25)<.18) {
                std::vector<QPointF> arc;
                for(int i=0;i<=20;++i){double u=i/20.;arc.emplace_back(m_origin.x()+(f.right()-m_origin.x())*u,m_origin.y()-90*u+std::sin(i*2.1+t*13)*4*std::sin(u*3.14159));}
                ribbon(arc,.65);
            }
            // Two bounded, cached strikes per activation. No per-frame random work.
            const int strikeSlot=int(std::floor((t-.8)/2.1));
            if(strikeSlot>=0 && (m_continuous || strikeSlot<2)) {
                if(node->strikeSlot!=strikeSlot) {
                    node->strikeSlot=strikeSlot;
                    auto *random=QRandomGenerator::global();
                    node->strikeDelay=random->generateDouble()*.3;
                    node->strikeDuration=.32+random->generateDouble()*.12;
                    int direction=random->bounded(4);QPointF from,to;
                    if(direction==0){from={f.left()+f.width()*(.2+random->generateDouble()*.6),f.top()+20};to={f.left()+f.width()*(.2+random->generateDouble()*.6),f.bottom()};}
                    else if(direction==1){from=f.topLeft()+QPointF(20,20);to=f.bottomRight();}
                    else if(direction==2){from=f.topRight()+QPointF(-20,20);to=f.bottomLeft();}
                    else{from={f.left()+20,f.top()+f.height()*(.2+random->generateDouble()*.6)};to={f.right(),f.top()+f.height()*(.2+random->generateDouble()*.6)};}
                    QPointF d=to-from;double length=std::max(1.,std::hypot(d.x(),d.y()));QPointF normal(-d.y()/length,d.x()/length);
                    node->strike.clear();node->strike.reserve(33);
                    for(int i=0;i<=32;++i){double u=i/32.;node->strike.push_back(from+d*u+normal*((random->generateDouble()-.5)*65*std::sin(u*3.14159265)));}
                    node->branches.clear();
                    // Alternate the original bolt with a two-branch variant.
                    if(strikeSlot%2==1) for(int branch=0;branch<2;++branch) {
                        QPointF start=node->strike[branch==0?11:22];
                        double side=branch==0?1.:-1.;
                        QPointF end=start+d*.16+normal*(side*std::min(180.,length*.22));
                        end.setX(std::clamp(end.x(),f.left()+12,f.right()-12));
                        end.setY(std::clamp(end.y(),f.top()+12,f.bottom()-12));
                        std::vector<QPointF> path;
                        for(int i=0;i<=12;++i){double u=i/12.;path.push_back(start+(end-start)*u+normal*((random->generateDouble()-.5)*30*std::sin(u*3.14159265)));}
                        node->branches.push_back(std::move(path));
                    }
                    node->sparks.clear();node->sparks.reserve(48);
                    double inward=std::atan2(f.center().y()-to.y(),f.center().x()-to.x());
                    for(int i=0;i<48;++i){double a=inward+(random->generateDouble()-.5)*3.4,speed=110+random->generateDouble()*260;
                        // A few slower sparks spill into the existing transparent margin.
                        if(i<12){a=inward+3.14159265+(random->generateDouble()-.5)*1.2;speed=38+random->generateDouble()*22;}node->sparks.emplace_back(std::cos(a)*speed,std::sin(a)*speed);}
                }
                double age=t-(.8+strikeSlot*2.1+node->strikeDelay);
                lightning(node->strike,age,node->strikeDuration,1.);
                for(size_t branch=0;branch<node->branches.size();++branch)
                    lightning(node->branches[branch],age-.025*(branch+1),node->strikeDuration,.7);
                double impactAge=age-.09;
                if(impactAge>=0 && impactAge<.95 && !node->strike.empty()) {
                    if(node->soundSlot!=strikeSlot) {
                        node->soundSlot=strikeSlot;
                        QMetaObject::invokeMethod(this,[this]{emit lightningHit();},Qt::QueuedConnection);
                    }
                    for(size_t tip=0;tip<=node->branches.size();++tip) {
                    QPointF hit=tip==0?node->strike.back():node->branches[tip-1].back();
                    const double edgeDistance=std::min({std::abs(hit.x()-f.left()),std::abs(hit.x()-f.right()),std::abs(hit.y()-f.top()),std::abs(hit.y()-f.bottom())});
                    if(edgeDistance>1.)continue;
                    double fade=std::pow(1-impactAge/.95,2);
                    auto bloom=[&](double radius,double alpha,bool white) {
                        for(int i=0;i<28;++i){double a=i/28.*6.2831853,b=(i+1)/28.*6.2831853;
                            vertex(hit,alpha*fade,white);vertex(hit+QPointF(std::cos(a),std::sin(a))*radius,0,white);vertex(hit+QPointF(std::cos(b),std::sin(b))*radius,0,white);}
                    };
                    bloom(100+impactAge*65,.38,false);bloom(42+impactAge*22,.55,false);bloom(18+impactAge*12,.9,true);
                    for(const auto &velocity:node->sparks) {
                        QPointF point=hit+velocity*impactAge+QPointF(0,65*impactAge*impactAge);
                        std::vector<QPointF> spark{point,point-velocity*.04};
                        softGlow(spark,15,fade*.22);strip(spark,2,fade*.95,true);
                    }
                    }
                }
            }
            // An occasional interior discharge: only branches reaching the frame spark.
            const int interiorSlot=int(std::floor((t-1.8)/3.5));
            if(interiorSlot>=0 && (m_continuous || interiorSlot==0)) {
                if(node->interiorSlot!=interiorSlot) {
                    node->interiorSlot=interiorSlot;node->interior.clear();node->interiorHits.clear();
                    auto *random=QRandomGenerator::global();
                    QPointF origin(f.left()+f.width()*(.25+random->generateDouble()*.5),f.top()+f.height()*(.25+random->generateDouble()*.5));
                    double heading=random->generateDouble()*6.2831853;
                    for(int branch=0;branch<3;++branch) {
                        double angle=heading+branch*2.0943951+(random->generateDouble()-.5)*.6;
                        QPointF direction(std::cos(angle),std::sin(angle)),normal(-direction.y(),direction.x());
                        double edge=std::min(direction.x()>0?(f.right()-origin.x())/direction.x():(f.left()-origin.x())/direction.x(),direction.y()>0?(f.bottom()-origin.y())/direction.y():(f.top()-origin.y())/direction.y());
                        bool hit=branch==0 || random->generateDouble()<.35;
                        double distance=hit?edge:edge*(.3+random->generateDouble()*.35);
                        std::vector<QPointF> path;
                        for(int i=0;i<=20;++i){double u=i/20.;path.push_back(origin+direction*(distance*u)+normal*((random->generateDouble()-.5)*42*std::sin(u*3.14159265)));}
                        node->interior.push_back(std::move(path));node->interiorHits.push_back(hit);
                    }
                }
                double age=t-(1.8+interiorSlot*3.5);
                for(const auto &path:node->interior)lightning(path,age,.38,.8);
                if(age>=.09 && age<.8) {
                    if(node->interiorSoundSlot!=interiorSlot){node->interiorSoundSlot=interiorSlot;QMetaObject::invokeMethod(this,[this]{emit lightningHit();},Qt::QueuedConnection);}
                    double elapsed=age-.09,fade=std::pow(1-elapsed/.71,2);
                    for(size_t branch=0;branch<node->interior.size();++branch) if(node->interiorHits[branch]) {
                        QPointF hit=node->interior[branch].back();
                        for(int i=0;i<24;++i){double a=i/24.*6.2831853,b=(i+1)/24.*6.2831853;vertex(hit,fade*.7,true);vertex(hit+QPointF(std::cos(a),std::sin(a))*65,0,false);vertex(hit+QPointF(std::cos(b),std::sin(b))*65,0,false);}
                        for(int i=0;i<20;++i){double a=i*2.399963;QPointF velocity(std::cos(a)*(65+i*5),std::sin(a)*(65+i*5));QPointF point=hit+velocity*elapsed;std::vector<QPointF> spark{point,point-velocity*.035};softGlow(spark,10,fade*.18);strip(spark,1.6,fade*.9,true);}
                    }
                }
            }
            // Small, staggered branch arcs stay around panel/window edges.
            for(int k=0;k<3;++k) {
                double age=(m_continuous?std::fmod(t,5.2):t)-(1.5+k*1.13);
                if(age<0 || age>.27)continue;
                QPointF from=boundary(.13+k*.29),toward=f.center()-from;
                double length=std::max(1.,std::hypot(toward.x(),toward.y()));
                QPointF direction=toward/length,normal(-direction.y(),direction.x());
                std::vector<QPointF> arc;
                for(int i=0;i<=12;++i){double u=i/12.;arc.push_back(from+direction*(u*(90+k*24))+normal*(std::sin(i*2.7+k)*9*std::sin(u*3.14159265)));}
                ribbon(arc,std::sin(age/.27*3.14159265)*.65);
            }
            for(int i=0;i<44;++i) {
                double u=std::fmod(i/44.+t*.027,1.);double x,y;
                if(i%2){x=f.right()-10-std::sin(t+i)*15;y=f.top()+u*f.height();}
                else{x=f.left()+u*f.width();y=f.top()+12+std::sin(u*7+t)*18;}
                std::vector<QPointF> dot{{x-1,y},{x+1,y}}; strip(dot,2,.55,true);strip(dot,9,.025);
            }
            }
        } else {
            std::vector<QPointF> outline{{f.left()+2,f.top()+2},{f.right()-2,f.top()+2},{f.right()-2,f.bottom()-2},{f.left()+2,f.bottom()-2},{f.left()+2,f.top()+2}};
            ribbon(outline,.7);
        }
    }
    auto *g=node->geometry();if(g->vertexCount()!=int(vertices.size()))g->allocate(vertices.size());
    std::copy(vertices.begin(),vertices.end(),g->vertexDataAsColoredPoint2D());
    g->markVertexDataDirty();node->markDirty(QSGNode::DirtyGeometry);
    return node;
}
