#include "include/record_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>

#define RECORD_LINUX_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), record_linux_plugin_get_type(), \
                              RecordLinuxPlugin))

struct _RecordLinuxPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(RecordLinuxPlugin, record_linux_plugin, g_object_get_type())

// Stub implementation - does nothing
static void record_linux_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(record_linux_plugin_parent_class)->dispose(object);
}

static void record_linux_plugin_class_init(RecordLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = record_linux_plugin_dispose;
}

static void record_linux_plugin_init(RecordLinuxPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  // Stub - return not implemented
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

void record_linux_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  RecordLinuxPlugin* plugin = RECORD_LINUX_PLUGIN(
      g_object_new(record_linux_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "record_linux", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}

