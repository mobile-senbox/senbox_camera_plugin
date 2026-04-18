// import 'package:flutter_test/flutter_test.dart';
// import 'package:senbox_camera_plugin/senbox_camera_plugin.dart';
// import 'package:senbox_camera_plugin/senbox_camera_plugin_platform_interface.dart';
// import 'package:senbox_camera_plugin/senbox_camera_plugin_method_channel.dart';
// import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// class MockSenboxCameraPluginPlatform
//     with MockPlatformInterfaceMixin
//     implements SenboxCameraPluginPlatform {

//   @override
//   Future<String?> getPlatformVersion() => Future.value('42');
// }

// void main() {
//   final SenboxCameraPluginPlatform initialPlatform = SenboxCameraPluginPlatform.instance;

//   test('$MethodChannelSenboxCameraPlugin is the default instance', () {
//     expect(initialPlatform, isInstanceOf<MethodChannelSenboxCameraPlugin>());
//   });

//   test('getPlatformVersion', () async {
//     // SenboxCameraPlugin senboxCameraPlugin = SenboxCameraPlugin();
//     MockSenboxCameraPluginPlatform fakePlatform = MockSenboxCameraPluginPlatform();
//     SenboxCameraPluginPlatform.instance = fakePlatform;

//     // expect(await senboxCameraPlugin.getPlatformVersion(), '42');
//   });
// }
