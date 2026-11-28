#!/usr/bin/env python3
"""Tray overflow test fixture for the Monarch VM.

Spawns N real StatusNotifierItem (SNI) services on the session D-Bus so a
live Quickshell bar's SystemTray model fills up and the "+N" overflow popup
can be exercised end to end (including QMP-driven click-through tests).

FIXTURE VS REAL SERVICE EVIDENCE: these items are synthetic test services
owned by this script (bus names org.monarch.TrayFixture*). They travel the
same watcher/protocol path as real applets (nm-applet, blueman, ...) and
prove the bar/popup handle real SNI protocol traffic; they prove nothing
about any specific real application's behavior. Label VM screenshots and
logs accordingly.

Every protocol call is logged as one line, to stdout and to --log:
    REGISTERED <n> <bus-name>
    ACTIVATE <id> <x> <y>          (left click)
    SECONDARY <id> <x> <y>         (middle click)
    CONTEXTMENU <id> <x> <y>       (right click path when no menu is used)
    MENUCLICK <id> <menu-item-id>  (dbusmenu item clicked after display())

Usage: python3 tray_fixture.py [--items N] [--log PATH]
Requires: python-gobject (in install/monarch-base.packages), a session bus,
and a running StatusNotifierWatcher (Quickshell provides one while the bar
is up; the fixture retries registration until the watcher appears).
"""

import argparse
import fcntl
import os
import sys
import time

from gi.repository import Gio, GLib

LOG_FILE = "/tmp/tray-fixture-calls.log"

SNI_XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionMovieName" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="XAyatanaLabel" type="s" access="read"/>
    <property name="XAyatanaLabelGuide" type="s" access="read"/>
    <property name="XAyatanaOrderingIndex" type="u" access="read"/>
    <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
    <signal name="NewIcon"/><signal name="NewTitle"/><signal name="NewStatus"/>
    <signal name="NewToolTip"/><signal name="NewAttentionIcon"/><signal name="NewOverlayIcon"/>
  </interface>
</node>
"""

DBUSMENU_XML = """
<node>
  <interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconThemePath" type="as" access="read"/>
    <method name="GetLayout">
      <arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/>
      <arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg type="ai" direction="in"/><arg type="as" direction="in"/>
      <arg type="a(ia{sv})" direction="out"/>
    </method>
    <method name="GetProperty">
      <arg type="i" direction="in"/><arg type="s" direction="in"/>
      <arg type="v" direction="out"/>
    </method>
    <method name="Event">
      <arg type="i" direction="in"/><arg type="s" direction="in"/>
      <arg type="v" direction="in"/><arg type="u" direction="in"/>
    </method>
    <method name="EventGroup">
      <arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/>
    </method>
    <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
    <method name="AboutToShowGroup">
      <arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/>
    </method>
    <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
  </interface>
</node>
"""

SNI_INFO = Gio.DBusNodeInfo.new_for_xml(SNI_XML).interfaces[0]
MENU_INFO = Gio.DBusNodeInfo.new_for_xml(DBUSMENU_XML).interfaces[0]


class Logger:
    def __init__(self, path):
        self.path = path

    def __call__(self, line):
        line = "%.3f %s" % (time.time(), line)
        print(line, flush=True)
        try:
            with open(self.path, "a") as fh:
                fcntl.flock(fh, fcntl.LOCK_EX)
                fh.write(line + "\n")
        except OSError:
            pass


class FixtureItem:
    """One StatusNotifierItem plus a one-entry dbusmenu for it."""

    def __init__(self, index, log):
        # Each item gets its own bus connection: real SNIs are separate
        # processes, and one connection cannot export two objects at the
        # same path.
        addr = os.environ["DBUS_SESSION_BUS_ADDRESS"]
        self.conn = Gio.DBusConnection.new_for_address_sync(
            addr,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None)
        conn = self.conn
        self.index = index
        self.log = log
        self.bus_name = "org.monarch.TrayFixture%d" % index
        self.title = "Fixture Item %d" % index
        self.menu_entry_id = 100 + index
        self.reg_ids = []
        Gio.bus_own_name_on_connection(conn,
            self.bus_name, Gio.BusNameOwnerFlags.NONE, None, None)
        self.reg_ids.append(conn.register_object(
            "/StatusNotifierItem", SNI_INFO,
            self._sni_method, self._sni_prop, None))
        self.reg_ids.append(conn.register_object(
            "/MenuBar", MENU_INFO, self._menu_method, self._menu_prop, None))

    # ---- org.kde.StatusNotifierItem -------------------------------------
    def _sni_method(self, conn, sender, path, iface, method, params, invocation):
        if method == "Activate":
            self.log("ACTIVATE %d %d %d" % (self.index, params[0], params[1]))
        elif method == "SecondaryActivate":
            self.log("SECONDARY %d %d %d" % (self.index, params[0], params[1]))
        elif method == "ContextMenu":
            self.log("CONTEXTMENU %d %d %d" % (self.index, params[0], params[1]))
        elif method == "Scroll":
            pass
        invocation.return_value(None)

    def _sni_prop(self, conn, sender, path, iface, name):
        props = {
            "Category": GLib.Variant("s", "ApplicationStatus"),
            "Id": GLib.Variant("s", "tray-fixture-%d" % self.index),
            "Title": GLib.Variant("s", self.title),
            "Status": GLib.Variant("s", "Active"),
            "WindowId": GLib.Variant("i", 0),
            "IconThemePath": GLib.Variant("s", ""),
            "IconName": GLib.Variant("s", "dialog-information"),
            "IconPixmap": GLib.Variant("a(iiay)", []),
            "OverlayIconName": GLib.Variant("s", ""),
            "OverlayIconPixmap": GLib.Variant("a(iiay)", []),
            "AttentionIconName": GLib.Variant("s", ""),
            "AttentionIconPixmap": GLib.Variant("a(iiay)", []),
            "AttentionMovieName": GLib.Variant("s", ""),
            "ToolTip": GLib.Variant("(sa(iiay)ss)",
                                    ("dialog-information", [], self.title, "fixture")),
            "Menu": GLib.Variant("o", "/MenuBar"),
            "ItemIsMenu": GLib.Variant("b", False),
            "XAyatanaLabel": GLib.Variant("s", ""),
            "XAyatanaLabelGuide": GLib.Variant("s", ""),
            "XAyatanaOrderingIndex": GLib.Variant("u", self.index),
        }
        return props.get(name)

    # ---- com.canonical.dbusmenu ------------------------------------------
    def _item_props(self, item_id):
        if item_id == 0:
            return {"children-display": GLib.Variant("s", "submenu"),
                    "enabled": GLib.Variant("b", True)}
        return {"label": GLib.Variant("s", "Fixture action %d" % self.index),
                "enabled": GLib.Variant("b", True),
                "visible": GLib.Variant("b", True),
                "icon-name": GLib.Variant("s", "dialog-information")}

    def _layout(self, parent_id, depth):
        if parent_id == self.menu_entry_id or (parent_id == 0 and depth == 0):
            return (parent_id, self._item_props(parent_id), [])
        children = []
        if parent_id == 0:
            children.append(GLib.Variant("(ia{sv}av)", (
                self.menu_entry_id,
                self._item_props(self.menu_entry_id), [])))
        return (parent_id, self._item_props(parent_id), children)

    def _menu_method(self, conn, sender, path, iface, method, params, invocation):
        if method == "GetLayout":
            parent_id, depth, _names = params
            layout = self._layout(parent_id, depth)
            invocation.return_value(GLib.Variant("(u(ia{sv}av))", (1, layout)))
        elif method == "GetGroupProperties":
            ids, _names = params
            out = [(i, self._item_props(i)) for i in ids]
            invocation.return_value(GLib.Variant("(a(ia{sv}))", (out,)))
        elif method == "GetProperty":
            item_id, prop = params
            invocation.return_value(GLib.Variant("(v)", (self._item_props(item_id)[prop],)))
        elif method == "Event":
            item_id, event_id, _data, _ts = params
            if event_id == "clicked":
                self.log("MENUCLICK %d %d" % (self.index, item_id))
            invocation.return_value(None)
        elif method == "EventGroup":
            for item_id, event_id, _data, _ts in params[0]:
                if event_id == "clicked":
                    self.log("MENUCLICK %d %d" % (self.index, item_id))
            invocation.return_value(GLib.Variant("(ai)", ([],)))
        elif method == "AboutToShow":
            invocation.return_value(GLib.Variant("(b)", (False,)))
        elif method == "AboutToShowGroup":
            invocation.return_value(GLib.Variant("(aiai)", ([], [])))
        else:
            invocation.return_value(None)

    def _menu_prop(self, conn, sender, path, iface, name):
        props = {
            "Version": GLib.Variant("u", 4),
            "Status": GLib.Variant("s", "normal"),
            "IconThemePath": GLib.Variant("as", []),
        }
        return props.get(name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--items", type=int, default=5)
    ap.add_argument("--log", default=LOG_FILE)
    args = ap.parse_args()

    log = Logger(args.log)
    try:
        os.unlink(args.log)
    except OSError:
        pass

    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    items = [FixtureItem(i + 1, log) for i in range(args.items)]

    state = {"registered": 0}

    def try_register():
        for item in items:
            if getattr(item, "registered", False):
                continue
            try:
                conn.call_sync(
                    "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                    "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
                    GLib.Variant("(s)", (item.bus_name,)),
                    None, Gio.DBusCallFlags.NONE, 2000, None)
                item.registered = True
                state["registered"] += 1
                log("REGISTERED %d %s" % (item.index, item.bus_name))
            except GLib.GError:
                pass
        if state["registered"] == len(items):
            log("READY %d items registered with the watcher" % len(items))
            return GLib.SOURCE_REMOVE
        return GLib.SOURCE_CONTINUE

    GLib.timeout_add(1000, try_register)
    log("WAITING for org.kde.StatusNotifierWatcher (%d items)" % len(items))
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
