# TODO

## P0 — 开源前必须完成

- [x] 国际化（i18n）：英文为默认语言，中文翻译 154 条，跟随系统语言自动切换
- [x] 应用图标：蓝紫渐变剪贴板 + 纸飞机，含 .icns 和运行时渲染
- [x] 辅助功能权限引导：首次启动欢迎窗口，检测辅助功能权限并引导授权
- [x] 忽略应用选择器：可视化应用列表替代手填 Bundle ID
- [ ] 添加 LICENSE 文件
- [ ] Accessibility 标注：为 View 添加 `accessibilityLabel`，支持 VoiceOver

## P1 — 开源后应尽快补齐

- [ ] CI/CD：GitHub Actions 自动构建和测试
- [ ] 代码签名 + 公证：替换 ad-hoc 签名，通过 Gatekeeper
- [ ] Homebrew Cask / DMG 分发：用户无需自行编译
- [ ] 自动更新机制（Sparkle 或类似方案）
- [ ] README 截图 / GIF 演示
- [ ] CONTRIBUTING.md 贡献指南
- [ ] CHANGELOG 版本变更记录

## P2 — 后续增强

- [ ] 富文本 / 文件拖拽支持
- [ ] iCloud 同步（跨设备历史）
- [ ] 插件系统（自定义内容类型和动作）
- [ ] 全局 Paste-as-plain-text 功能
- [ ] 深色/浅色主题手动切换
