"""Local mouse/keyboard preview; not an EEG/Neuralife host implementation."""
import os,sys
from pathlib import Path
os.environ.setdefault('QT_QUICK_BACKEND','rhi')
if sys.platform == 'darwin': os.environ.setdefault('QSG_RHI_BACKEND','metal')
from PySide6.QtCore import QObject,Slot,QUrl,Qt,QSize,QEvent
from PySide6.QtGui import QGuiApplication,QColor,QWindow
from PySide6.QtQuick import QQuickView
from shiboken6 import isValid

class PreviewBridge(QObject):
    @Slot(str,str)
    def record(self,name,value):
        if name.endswith(('finished','completed','finish')): print(name,value,flush=True)

class PreviewKeys(QObject):
    """Handle window commands before game buttons can consume their keys."""
    def __init__(self,view): super().__init__(view);self.view=view
    def toggle(self):
        self.view.showNormal() if self.view.visibility()==QWindow.FullScreen else self.view.showFullScreen()
    def eventFilter(self,watched,event):
        if not isValid(self.view):return False
        if event.type()==QEvent.ShortcutOverride and (event.key()==Qt.Key_F11 or (event.key()==Qt.Key_Escape and self.view.visibility()==QWindow.FullScreen)):
            event.accept()
            return True
        if event.type()==QEvent.KeyPress and (event.key()==Qt.Key_F11 or (event.key()==Qt.Key_Escape and self.view.visibility()==QWindow.FullScreen)):
            if not event.isAutoRepeat():self.toggle()
            return True
        return False

def create_preview(argv=None):
    app=QGuiApplication.instance() or QGuiApplication(argv or sys.argv)
    bridge=PreviewBridge()
    view=QQuickView()
    view.setColor(QColor('#050505'))
    view.setResizeMode(QQuickView.SizeRootObjectToView)
    view.setTitle('Neuralife · 七款游戏响应式预览')
    view.engine().rootContext().setContextProperty('previewBridge',bridge)
    view.setSource(QUrl.fromLocalFile(str(Path(__file__).with_name('Preview.qml'))))
    if view.status()==QQuickView.Error:raise RuntimeError('Preview.qml could not be loaded')
    keys=PreviewKeys(view);view.installEventFilter(keys)
    view.rootObject().fullscreenRequested.connect(keys.toggle)
    def visibility_changed(visibility):
        if not isValid(view):return
        item=view.rootObject()
        if item is not None:item.setProperty('fullscreen',visibility==QWindow.FullScreen)
    view.visibilityChanged.connect(visibility_changed)
    view.resize(1100,830);view.setMinimumSize(QSize(800,640));view.show()
    def active_changed(state):
        if state!=Qt.ApplicationActive and isValid(view):
            item=view.rootObject()
            if item is not None:item.backgroundPause()
    app.applicationStateChanged.connect(active_changed)
    return app,view,bridge,keys

if __name__=='__main__':
    app,view,bridge,keys=create_preview()
    sys.exit(app.exec())
