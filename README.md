# 学习通作业本

一个使用 Flutter 编写的学习通（超星）作业管理 Android 应用：自动读取课程作业，按「全部 / 未交 / 已交 / 已截止」分类展示，支持长按多选并将作业截止时间导入系统日历，在截止前 2 小时提醒。

> 非官方客户端，仅用于个人学习管理。应用只读查询，不提供签到、刷课、答题或作业提交功能。

## 功能特性

- 学习通账号密码登录，自动保存会话，Cookie 失效时自动重登
- 汇总所有课程的作业、状态与截止时间
- 顶部四类筛选：全部 / 未交 / 已交 / 已截止（已交不包含已截止的作业）
- 截止倒计时与紧迫度提示
- 本地缓存：每天自动获取一次，当天再次打开直接读取缓存；只有手动刷新才重新请求
- 长按作业卡片进入多选，支持全选、反选、取消
- 长按不松手拖动可连续勾选，拖到列表边缘自动滚动
- 一键把所选作业写入系统日历，提醒时间为截止前 2 小时，自动跳过重复日程
- 退出登录同时清除账号凭据、会话与作业缓存

## 技术栈

- Flutter 3.44 / Dart 3.12
- `shared_preferences` 本地缓存与会话存储
- `encrypt`（AES-128-CBC）处理学习通登录参数
- Android 原生 `CalendarContract` 写入日历与提醒
- Android 包名：`com.frandre.homework_list`

## 快速开始

### 环境要求

- Flutter SDK 3.44 或更高
- Android SDK（minSdk 使用 Flutter 默认值）
- JDK 17

### 构建

```bash
flutter pub get
flutter build apk --release
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`

调试构建：

```bash
flutter build apk --debug
```

## 使用说明

1. 首次启动输入学习通手机号与密码登录。
2. 主界面读取全部课程作业；顶部可切换「全部 / 未交 / 已交 / 已截止」。
3. 长按任意作业卡片进入多选；选中后可全选、反选、取消，或长按不松手拖动快速多选。
4. 点击底部「导入日历」，授予日历读写权限后写入日程。
5. 日程时间取作业截止时间，提醒时间为截止前 2 小时；已过期或没有截止时间的作业不会写入。
6. 顶部刷新按钮或下拉刷新会立即重新获取；否则当天仅自动获取一次。

## 项目结构

```
lib/
  main.dart                 应用入口与登录态切换
  theme.dart                配色与主题
  models/homework.dart      作业模型与分类规则
  services/
    chaoxing_client.dart    学习通登录与作业抓取
    homework_cache.dart     作业本地缓存
    calendar_service.dart   日历原生通道封装
    session_store.dart      凭据与 Cookie 存储
  screens/
    login_screen.dart       登录页
    home_screen.dart        作业列表、多选与日历导入
android/
  app/src/main/kotlin/com/frandre/homework_list/MainActivity.kt
                            日历权限与日程写入
```

## 数据与隐私

- 账号、密码、Cookie 与作业缓存仅保存在本机，不会上传到第三方服务器。
- 应用只读：不会提交作业，也不会修改学习通上的任何数据。
- 退出登录会删除本机保存的凭据、会话和作业缓存。

## 免责声明

本项目为个人学习辅助工具，与学习通/超星官方无关。学习通接口可能随时调整导致功能失效；请遵守学校与平台的使用规定，合理使用。

## 版权

© 2026 FrandreJoestar. All rights reserved.
