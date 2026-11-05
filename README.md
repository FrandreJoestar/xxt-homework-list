<p align="center">
  <img src="icon.png" width="112" alt="学习通作业本图标" />
</p>

<h1 align="center">学习通作业本</h1>

<p align="center">
  用 Flutter 打造的学习通（超星）作业截止管理 Android 应用
</p>

<p align="center">
  自动汇总作业 · 四类筛选 · 详情速览 · 一键导入系统日历
</p>

> 非官方客户端，仅用于个人学习管理。应用只读查询，不提供签到、刷课、答题或作业提交功能。

## 项目简介

学习通作业本会登录学习通账号，读取全部课程作业及截止时间，并按「全部 / 未交 / 已交 / 已截止」分类展示。点击作业卡片可查看题量、满分、作答时间与得分；长按卡片可多选，选择提前提醒时间后一键写入系统日历，在截止前收到提醒。

当前版本：**v1.2.2**

## 功能特性

| 模块 | 能力 |
| --- | --- |
| 账号 | 学习通手机号 / 密码登录，自动保存会话，Cookie 失效时自动重登 |
| 作业 | 汇总全部课程的作业标题、课程、状态与截止时间 |
| 详情 | 点击卡片弹出详情卡片：题量、满分、作答起止时间、得分，可直接添加到日历 |
| 筛选 | 全部 / 未交 / 已交 / 已截止；「已交」不包含已截止的作业 |
| 切换 | 点击顶部分类或左右滑动列表切换选项卡，页面跟随手指滑动并带过渡动画 |
| 提醒 | 截止倒计时与紧迫度配色；临近截止更醒目 |
| 多选 | 长按卡片进入多选，支持全选、反选、取消 |
| 快速多选 | 长按不松手拖动连续勾选；往回滑会取消经过的卡片；拖到列表边缘自动滚动 |
| 刷新 | 下拉刷新或点击右上角刷新；刷新过程可随时取消，不会影响已有列表 |
| 日历 | 导入前通过天 / 小时 / 分钟滚轮选择提前提醒时间，默认 2 小时 |
| 震动反馈 | 拖动滚轮改变时间数字时发出轻微震动 |
| 去重 | 相同标题与截止时间的日程自动跳过，重复导入不会产生重复日程 |
| 缓存 | 每天自动获取一次，当天再次打开直接读取本地缓存；手动刷新才重新请求 |
| 更新 | 启动时检查 version.json，按设备架构自动选择 arm64-v8a / armeabi-v7a 安装包并跳转浏览器下载 |
| 提示 | 列表顶部展示「点击看详情、长按多选」的操作提示 |
| 隐私 | 凭据、Cookie 与作业缓存仅保存在本机；退出登录会清空 |

## 使用说明

1. 首次启动输入学习通手机号与密码登录。
2. 主界面展示全部课程作业，顶部切换「全部 / 未交 / 已交 / 已截止」，也可在列表上左右滑动切换。
3. 点击作业卡片弹出详情，查看题量、满分、作答时间与得分；底部可「添加到日历」或「取消」。
4. 长按任意作业卡片进入多选；点击卡片可勾选或取消。
5. 多选状态下不松手拖动可连续勾选，往回滑会取消经过的卡片；拖到列表上下边缘会自动滚动。
6. 多选状态下可使用顶部「全选 / 反选 / 取消」。
7. 点击底部「导入日历」，在底部滚轮面板中选择提前提醒时间。
8. 确认后授予日历读写权限，应用会把所选作业写入系统日历。
9. 日程事件时间取作业截止时间，提醒时间 = 截止时间 − 提前量。
10. 已过期或没有截止时间的作业不会写入日历。

> 当天已经获取过数据时，重新打开应用不会联网；点击右上角刷新按钮或下拉刷新可立即重新获取。刷新过程中，右上角刷新按钮会变为「×」，列表顶部也会出现「取消刷新」，点击即可中止本次刷新。

## 技术栈

- Flutter 3.44 / Dart 3.12
- `shared_preferences`：凭据、Cookie、作业缓存
- `encrypt`：学习通登录参数的 AES-128-CBC 加密
- `package_info_plus`：读取当前安装版本
- `url_launcher`：打开更新下载页
- GitHub Actions：打 tag 自动构建并发布 APK 与 version.json
- Android 原生 `CalendarContract`：日历写入与提醒
- Android 包名：`com.frandre.homework_list`
- 应用显示名：学习通作业本

## 快速开始

### 环境要求

- Flutter SDK 3.44 或更高
- Android SDK
- JDK 17

### 获取依赖

```bash
flutter pub get
```

### 构建 APK

```bash
# 调试包
flutter build apk --debug

# 发布包
flutter build apk --release
```

产物路径：

- 调试：`build/app/outputs/flutter-apk/app-debug.apk`
- 发布：`build/app/outputs/flutter-apk/app-release.apk`

### 开发校验

```bash
flutter analyze
flutter test
```

## 项目结构

```
lib/
  main.dart                   应用入口与登录态切换
  theme.dart                  配色与 Material 3 主题
  models/
    homework.dart             作业模型、详情模型、分类规则与唯一标识
  services/
    chaoxing_client.dart      学习通登录、课程与作业抓取、截止时间与作业详情解析
    homework_cache.dart       作业列表本地缓存（按天判定）
    calendar_service.dart     日历原生通道封装
    session_store.dart        凭据与 Cookie 本地存储
    update_service.dart       版本检查、加速源与下载地址解析
  screens/
    login_screen.dart         登录页
    home_screen.dart          作业列表、分类滑动切换、详情弹窗、多选与日历导入
  utils/
    reminder_text.dart        提前提醒时间文案格式化
  widgets/
    reminder_picker.dart      天 / 小时 / 分钟滚轮选择器
    update_dialog.dart        新版本提示弹窗
android/
  app/src/main/kotlin/com/frandre/homework_list/MainActivity.kt
                              日历权限申请与日程写入
.github/
  workflows/release.yml       打 tag 自动构建并发布 APK + version.json
```

## 数据与缓存

- 首次启动或缓存过期时，自动登录并扫描全部课程作业。
- 获取成功后，作业列表、读取失败的课程名和保存时间写入本机缓存。
- 缓存保存于当天时，再次打开应用不发起网络请求。
- 顶部刷新按钮与下拉刷新会强制重新获取并更新缓存。
- 刷新过程中可随时取消：已发出的请求结果会被丢弃，现有列表保持不变。
- 刷新失败时保留原有缓存，不会清空列表。
- 作业是否截止根据当前时间动态判断，无需重新请求即可正确归档。

## 发布与自动更新

### 自动发布（推荐）

Release 不需要手动上传。推送一个 `v*` tag 即可触发 GitHub Actions 构建并发布：

```bash
git tag v1.2.0
git push origin v1.2.0
```

工作流 [`.github/workflows/release.yml`](.github/workflows/release.yml) 会自动：

1. 构建通用 APK 与按 ABI 拆分的 APK（arm64-v8a / armeabi-v7a）；
2. 上传 `xxt-homework-list.apk`、`xxt-homework-list-arm64-v8a.apk`、`xxt-homework-list-armeabi-v7a.apk`；
3. 生成并上传 `version.json`；
4. 创建或更新对应的 GitHub Release。

也可以在仓库 Actions 页面手动运行 `Release APK`，填写版本号。

### 正式签名（首次配置）

为了让后续版本能覆盖安装，需要在仓库 `Settings → Secrets and variables → Actions` 添加：

| Secret | 说明 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的 Base64 文本 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | key 别名 |
| `ANDROID_KEY_PASSWORD` | key 密码 |

生成 keystore 并转为 Base64：

```bash
keytool -genkey -v -keystore release.keystore -alias xxt -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 release.keystore
```

未配置时工作流会退回 debug 签名，但不同构建之间无法覆盖安装。

### 手动命令发布（可选）

已安装并登录 GitHub CLI 时，也可以直接命令发布：

```bash
flutter build apk --release --build-name=1.2.0 --build-number=2
gh release create v1.2.0 build/app/outputs/flutter-apk/app-release.apk \
  --title "学习通作业本 v1.2.0" --notes "更新说明"
```

手动发布时还需自行生成并上传 `version.json`。

### version.json 与更新检查

应用启动时会读取 Release 的 `latest/download/version.json`：

```json
{
  "version": "1.2.2",
  "build": 4,
  "apkUrl": "https://github.com/FrandreJoestar/xxt-homework-list/releases/latest/download/xxt-homework-list.apk",
  "apkUrls": {
    "arm64-v8a": "https://github.com/FrandreJoestar/xxt-homework-list/releases/latest/download/xxt-homework-list-arm64-v8a.apk",
    "armeabi-v7a": "https://github.com/FrandreJoestar/xxt-homework-list/releases/latest/download/xxt-homework-list-armeabi-v7a.apk"
  },
  "publishedAt": "2026-11-05T00:00:00Z"
}
```

新版本客户端会根据当前设备 ABI 从 `apkUrls` 选择对应分发包；旧版本或未匹配到 ABI 时回退到通用包 `apkUrl`。

检查顺序为直连加常用加速代理：

- 直连：`https://github.com/...`
- `https://gh-proxy.com/`
- `https://ghproxy.net/`
- `https://ghfast.top/`

任一源返回更高版本时弹窗提示；点击「去更新」会使用该源的加速地址打开浏览器下载 APK。全部源失败时静默忽略，不影响正常使用。

## 常见问题

**登录失败怎么办？**

请确认账号密码正确、网络可用。若学习通要求短信验证或图形验证码，需先在官方客户端完成验证后再尝试。

**为什么当天重新打开没有重新获取？**

这是每日缓存策略：当天只自动获取一次。需要最新数据时点击右上角刷新按钮或下拉刷新。

**刷新太慢或误触了怎么办？**

刷新过程中，右上角刷新按钮会变为「×」，列表顶部也有「取消刷新」，点击即可立即中止。已发出的请求会在后台自然结束，但结果会被丢弃，不会覆盖当前列表。

**点击作业卡片没有反应？**

详情需要联网读取作业详情页。若课程未开放作业详情、登录状态失效或网络异常，弹窗内会显示错误提示，此时仍可依据列表中的截止时间添加到日历。

**为什么启动时没有提示更新？**

应用仅在成功读取到更高的 `version.json` 版本时弹窗。若 GitHub 与所列加速源都无法访问，或当前已是最新版本，则不会提示；可稍后重新打开应用或前往 Releases 页面手动查看。

**导入日历后没有收到提醒？**

请检查系统是否授予了日历读写权限，并确认日历应用的通知权限已开启；同时确认日程写入到了你实际查看的日历账户中。

**会提交作业或修改学习通数据吗？**

不会。应用只做登录与只读查询，不提供提交、签到、刷课、答题等功能。

**支持 iOS 吗？**

当前版本面向 Android，日历写入能力基于 Android `CalendarContract` 实现。

## 更新日志

### v1.2.2

- Release 改为按 ABI 分包：arm64-v8a 约 18 MB、armeabi-v7a 约 16 MB，同时保留通用包
- 更新检查根据设备架构自动选择对应安装包，未匹配时回退通用包
- `version.json` 新增 `apkUrls` 字段

### v1.2.1

- 启用正式签名构建并发布 APK，后续版本可直接覆盖安装
- 发布流程自动生成 version.json，供应用内更新检查使用

### v1.2.0

- 点击作业卡片弹出详情卡片：题量、满分、作答起止时间、得分
- 详情卡片内可直接「添加到日历」，复用提前提醒时间选择
- 分类列表支持左右滑动切换选项卡，页面跟随手指滑动并带过渡动画
- 下拉刷新与手动刷新支持取消：右上角「×」或列表顶部「取消刷新」
- 长按拖拽多选时，反向滑动会取消经过卡片的选中状态
- 自动滚动改为逐帧平滑滚动，并缓存排序结果，减少拖选卡顿
- 列表顶部新增「点击看详情、长按多选」操作提示
- 启动时自动检查新版本，支持直连与 gh-proxy 等加速源，并弹窗跳转浏览器下载
- 新增 GitHub Actions 自动构建并发布 APK 与 version.json
- 支持通过 Secrets 配置正式签名，保证后续版本可覆盖安装

### v1.1.0

- 新增导入日历前的提前提醒时间选择器
- 支持天 / 小时 / 分钟三列滚轮，默认提前 2 小时
- 拖动滚轮数字时提供轻微震动反馈
- 日历提醒提前量改为按所选时间写入
- 完善 README

### v1.0.0

- 学习通登录与自动会话保持
- 全部课程作业抓取与四类筛选
- 每日一次自动获取 + 本地缓存
- 长按多选、全选 / 反选 / 取消、拖动快速多选
- 一键导入系统日历，截止前 2 小时提醒
- 应用图标、包名与版权信息

## 免责声明

本项目为个人学习辅助工具，与学习通 / 超星官方无关。学习通接口可能随平台调整而变化，若出现无法登录或读取失败，请以官方客户端为准。请遵守学校与平台的使用规定，合理使用。

## 版权

© 2026 FrandreJoestar. All rights reserved.
