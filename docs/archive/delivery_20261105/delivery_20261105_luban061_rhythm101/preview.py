"""Standalone keyboard/mock-BCI preview. Logs are JSONL; this is not an EEG decoder."""
import os,sys,json,argparse
from pathlib import Path
os.environ.setdefault('QT_QUICK_BACKEND','rhi')
from PySide6.QtCore import QObject,Slot,Signal,QUrl,Qt,QTimer,QElapsedTimer,QEvent,QSize,Property
from PySide6.QtGui import QGuiApplication,QColor
from PySide6.QtQuick import QQuickView
ROOT=Path(__file__).resolve().parent
class Bridge(QObject):
    tick=Signal(float)
    def __init__(self,log,config=None):
        super().__init__();self.log=log;self.events=[];self.finishes=[];self._config=config or {}
    @Property("QVariantMap", constant=True)
    def configValues(self):return self._config
    @Slot(str,str)
    def record(self,name,value):
        data={'name':name,'data':json.loads(value)};self.events.append(data)
        if self.log:
            with self.log.open('a',encoding='utf-8') as f:f.write(json.dumps(data,ensure_ascii=False)+'\n')
    @Slot(str)
    def finish(self,value):
        self.finishes.append(json.loads(value));self.record('preview.finish',value)
class Keys(QObject):
    def __init__(self,view):super().__init__(view);self.view=view
    def eventFilter(self,obj,e):
        if e.type() in (QEvent.KeyPress,QEvent.KeyRelease,QEvent.ShortcutOverride):
            names={Qt.Key_Left:'left',Qt.Key_A:'left',Qt.Key_Down:'down',Qt.Key_S:'down',Qt.Key_Up:'up',Qt.Key_W:'up',Qt.Key_Right:'right',Qt.Key_D:'right',Qt.Key_Space:'confirm',Qt.Key_Return:'confirm',Qt.Key_Enter:'confirm'}
            name=names.get(e.key())
            if name:
                e.accept()
                if e.type()!=QEvent.ShortcutOverride and not e.isAutoRepeat():self.view.rootObject().relayKey(name,e.type()==QEvent.KeyPress)
                return True
        return False

def create_preview(log=None,auto_tick=True,config=None):
    app=QGuiApplication.instance() or QGuiApplication(sys.argv)
    bridge=Bridge(log,config);view=QQuickView();view.setResizeMode(QQuickView.SizeRootObjectToView)
    view.setTitle('Neuralife · 四向律动');view.setColor(QColor('#050505'));view.engine().rootContext().setContextProperty('previewBridge',bridge)
    view.setSource(QUrl.fromLocalFile(str(ROOT/'Preview.qml')))
    if view.status()==QQuickView.Error:raise RuntimeError('Preview.qml load failed')
    keys=Keys(view);view.installEventFilter(keys);view.resize(1100,820);view.setMinimumSize(QSize(480,640));view.show()
    timer=QTimer(view);clock=QElapsedTimer();clock.start()
    def tick():
        dt=clock.nsecsElapsed()/1e9;clock.restart();bridge.tick.emit(dt)
    timer.timeout.connect(tick)
    if auto_tick:timer.start(16)
    app.applicationStateChanged.connect(lambda state:view.rootObject().backgroundPause() if state!=Qt.ApplicationActive else None)
    return app,view,bridge,keys,timer
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--log',type=Path,default=ROOT/'rhythm-session.jsonl');parser.add_argument('--config',type=Path,default=ROOT/'session-config.json');args=parser.parse_args()
    config=json.loads(args.config.read_text(encoding="utf-8")) if args.config.exists() else {}
    if not isinstance(config,dict):raise ValueError("配置文件应为JSON对象")
    app,view,bridge,keys,timer=create_preview(args.log,config=config)
    sys.exit(app.exec())
