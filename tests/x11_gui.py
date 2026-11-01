"""Input/capture helpers for the isolated Xvfb test display, never the user's desktop."""
import ctypes
import ctypes.util
import re
import subprocess
import time


def windows():
    result = subprocess.run(['xwininfo', '-root', '-tree'], capture_output=True, text=True, check=True)
    return [(int(m.group(1), 16), m.group(2)) for m in re.finditer(r'(0x[0-9a-f]+) "([^"]*)"', result.stdout)]


class Display:
    def __init__(self):
        self.x = ctypes.CDLL(ctypes.util.find_library('X11'))
        self.xt = ctypes.CDLL(ctypes.util.find_library('Xtst'))
        self.x.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x.XOpenDisplay.restype = ctypes.c_void_p
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError('No Xvfb display')
        for name, types in {
            'XRaiseWindow': [ctypes.c_void_p, ctypes.c_ulong],
            'XSetInputFocus': [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong],
            'XFlush': [ctypes.c_void_p],
            'XCloseDisplay': [ctypes.c_void_p],
            'XWarpPointer': [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint, ctypes.c_int, ctypes.c_int],
        }.items():
            getattr(self.x, name).argtypes = types
        self.x.XStringToKeysym.argtypes = [ctypes.c_char_p]
        self.x.XStringToKeysym.restype = ctypes.c_ulong
        self.x.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        self.x.XKeysymToKeycode.restype = ctypes.c_ubyte
        self.xt.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.xt.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]

    def focus(self, window):
        self.x.XRaiseWindow(self.display, window)
        self.x.XSetInputFocus(self.display, window, 2, 0)
        self.x.XFlush(self.display)

    def escape(self, window):
        self.focus(window)
        key = self.x.XKeysymToKeycode(self.display, self.x.XStringToKeysym(b'Escape'))
        for down in [1, 0]:
            self.xt.XTestFakeKeyEvent(self.display, key, down, 0)
        self.x.XFlush(self.display)
        time.sleep(0.2)

    def click(self, window, x, y):
        self.focus(window)
        self.x.XWarpPointer(self.display, 0, window, 0, 0, 0, 0, x, y)
        self.x.XFlush(self.display)
        time.sleep(0.1)
        self.xt.XTestFakeButtonEvent(self.display, 1, 1, 0)
        self.x.XFlush(self.display)
        time.sleep(0.15)
        self.xt.XTestFakeButtonEvent(self.display, 1, 0, 0)
        self.x.XFlush(self.display)

    def close(self):
        self.x.XCloseDisplay(self.display)
