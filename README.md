# React Native TrueSheet

[![CI](https://github.com/lodev09/react-native-true-sheet/actions/workflows/checks.yml/badge.svg)](https://github.com/lodev09/react-native-true-sheet/actions/workflows/checks.yml)
[![NPM Downloads](https://img.shields.io/npm/d18m/%40lodev09%2Freact-native-true-sheet)](https://www.npmjs.com/package/@lodev09/react-native-true-sheet)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/lodev09/react-native-true-sheet)

The true native bottom sheet experience for your React Native Apps. 💩

<img alt="React Native True Sheet - iPad" src="docs/static/img/preview-ipad.gif" width="744" /><br>
<img alt="React Native True Sheet - IOS" src="docs/static/img/preview-ios.gif" width="248" height="500" /><img alt="React Native True Sheet - Android" src="docs/static/img/preview-android.gif" width="248" height="500" /><img alt="React Native True Sheet - Web" src="docs/static/img/preview-web.gif" width="248" height="500" />

## Features

* ⚡ **Powered by Fabric** - Built on React Native's new architecture for maximum performance
* 🚀 **Fully Native** - Implemented in the native realm, zero JS hacks
* ♿ **Accessible** - Native accessibility and screen reader support out of the box
* 🔄 **Flexible API** - Use [imperative methods](https://sheet.lodev09.com/reference/methods#ref-methods) or [lifecycle events](https://sheet.lodev09.com/reference/events)
* ⌨️ **Keyboard Handling** - Built-in [keyboard handling](https://sheet.lodev09.com/guides/keyboard) with automatic adjustment
* 📐 **Side Sheets** - Native [side sheet](https://sheet.lodev09.com/guides/side-sheets) support for iPad and Android tablets
* 🪟 **Liquid Glass** - [iOS 26+ Liquid Glass](https://sheet.lodev09.com/guides/liquid-glass) support out of the box, featured in [Expo Blog](https://expo.dev/blog/how-to-create-apple-maps-style-liquid-glass-sheets)
* 🐎 **Reanimated** - First-class support for [react-native-reanimated](https://sheet.lodev09.com/guides/reanimated)
* 🧭 **React Navigation** - Built-in [sheet navigator](https://sheet.lodev09.com/guides/navigation) for seamless navigation integration
* 🌐 **Web Support** - Full [web support](https://sheet.lodev09.com/guides/web) out of the box

## Installation

> [!IMPORTANT]
> **Version 3.0+ requires React Native's New Architecture (Fabric)**
> For the old architecture, use version 2.x. See the [Migration Guide](https://sheet.lodev09.com/migration) for upgrading.

### Prerequisites

- React Native 0.81+
- New Architecture enabled
- Xcode 26.1+

### Compatibility

| TrueSheet | React Native | Expo SDK |
|-----------|--------------|----------|
| 3.7+      | 0.81+        | 54+      |
| 3.6       | 0.80         | 52-53    |

### Expo

```sh
npx expo install @lodev09/react-native-true-sheet
```

### Bare React Native

```sh
yarn add @lodev09/react-native-true-sheet
cd ios && pod install
```

## Documentation

- [Example](example)
- [Configuration](https://sheet.lodev09.com/reference/configuration)
- [Lifecycle Events](https://sheet.lodev09.com/reference/events)
- [React Navigation](https://sheet.lodev09.com/guides/navigation)
- [Troubleshooting](https://sheet.lodev09.com/troubleshooting)
- [Testing with Jest](https://sheet.lodev09.com/guides/jest)
- [Migrating to v3](https://sheet.lodev09.com/migration)

## Usage

```tsx
import { TrueSheet } from "@lodev09/react-native-true-sheet"

export const App = () => {
  const sheet = useRef<TrueSheet>(null)

  // Present the sheet ✅
  const present = async () => {
    await sheet.current?.present()
    console.log('horray! sheet has been presented 💩')
  }

  // Dismiss the sheet ✅
  const dismiss = async () => {
    await sheet.current?.dismiss()
    console.log('Bye bye 👋')
  }

  return (
    <View>
      <Button onPress={present} title="Present" />
      <TrueSheet
        ref={sheet}
        detents={['auto', 1]}
      >
        <Button onPress={dismiss} title="Dismiss" />
      </TrueSheet>
    </View>
  )
}
```

## SmartX 维护分支

`smartx-ios-sheet` 基于上游 3.11.14，版本 `3.11.14-smartx.2`。维护仓库为
[`mengjiu-cao/react-native-true-sheet`](https://github.com/mengjiu-cao/react-native-true-sheet)，
保留 3.x 的 scrollable、footer、detents 与事件 API，不迁移到 4.0 beta。

以下扩展仅用于 iOS；Android 显式忽略，不改变其外观：

| Prop | 默认与行为 |
| --- | --- |
| `edgeToEdge` | 默认 `false`；iOS 26+ 手机 page sheet 去除系统装饰缩放及外围留白。iPad、form 和显式窄宽度保持系统布局；全窗口 `maxContentWidth` 仍可启用。 |
| `backgroundColor` | 既有属性；自有 `TrueSheetRootView` 的原生背景层承载内容底色，不依赖应用补丁或给 UIKit 祖先涂色。 |
| `dimColor` / `dimOpacity` | 两者均省略时沿用系统蒙层，`edgeToEdge` 不改变此默认值。只传颜色时 opacity 为 0.5，只传 opacity 时颜色为黑。opacity 限制在 0–1，0 仍拦截模态背景触摸，`dimmed=false` 才允许穿透。 |
| `topBorderWidth` / `topBorderColor` | 默认宽度 0；颜色省略时用系统 separator。只描顶部及上两角，不描底边、不增加布局高度。 |
| `topLeftCornerRadius` / `topRightCornerRadius` | 独立覆盖上角，0 为直角；省略的一侧沿用 `cornerRadius` 或系统圆角。 |

```tsx
<TrueSheet
  edgeToEdge
  backgroundColor="#111111"
  dimColor="#000000"
  dimOpacity={0.5}
  cornerRadius={20}
  topBorderWidth={1}
  topBorderColor="#333333"
  topLeftCornerRadius={20}
  topRightCornerRadius={20}
>
  {children}
</TrueSheet>
```

SmartX 接入时不设置新的 border/radius 值，保持现有主题、抓手、内容与默认无描边；
示例中的描边仅展示可选能力。旧 Android 窗口高度、iOS 已可见输入框不反复滚动的修正已并入源码。
蒙层由库自行持有，关闭转场取消后恢复，堆叠与卸载释放保持原生命周期；不再修改 UIKit 的 DimmingView。

容器保留系统 `.pageSheet` 与原生转场，仅采用 native-sheet 的 UIView 背景承载和局部逆缩放。
`TrueSheetRootView` 管理背景、顶部描边和独立圆角；TrueSheet 原有 Fabric 内容容器、detents、
滚动、footer、键盘和事件 owner 保留。smartx.1 的间距测量/横向拉伸及 UIKit 祖先遮罩已移除。
补偿复用布局回调与已有转场跟踪，不添加常驻逐帧扫描，也不引入新的手势或动画状态机。
补偿同时抵消该wrapper的装饰缩放与位移；仅做 `1/a`、`1/d` 仍会留下短弹层的底部间距。
补偿子surface的bounds/center随wrapper逻辑尺寸同步，自有根容器铺满该尺寸，避免高度变化时autoresizing累计误差与像素取整缝隙；
不修改wrapper的frame/center、detent或外层交互容器位移，也不靠增加内容padding填缝。
逆缩放露出 UIKit 父视图命中范围以外的窄边缘时，自有透明 View 仅将该区域的命中转发到
原内容 View，沿用原手势识别器；不更改系统类、不扩大蒙层交互范围，关闭或堆叠时随补偿释放。

参考实现并非始终使用逆缩放：2026-09-15 的 `2f83dea3` 才由直接重置系统 transform 改为
在子 surface 上抵消缩放。当前实现仍有界识别本 sheet 的 UIKit `UIDropShadowView`；
该系统内部结构不是公共 API，不能把采用自有 root view 等同于去除了私有层级依赖。
纯几何烟测与原生编译不等于实际设备上的拖拽取消、堆叠和键盘验收。

构建与离线接入：`yarn install --immutable` → `yarn prepare` →
`yarn pack --out <输出目录>/react-native-true-sheet-3.11.14-smartx.2.tgz`。
应用通过仓库内 `file:` tarball 锁定本版本，无个人绝对路径依赖；更新原生代码后须重建开发包，JS reload 不生效。

## AI Skills

Skills are reusable AI capabilities that give your AI coding agent knowledge about TrueSheet. With the right skill loaded, your agent can pick the right patterns, avoid common mistakes, and generate correct code without you having to explain the library every time.

```sh
npx skills add lodev09/react-native-true-sheet
```

This will install the **TrueSheet Usage** skill into your project.

## That map is awesome!

Yes it is! Checkout [`@lugg/maps`](https://github.com/lugg/maps), a universal maps library for React Native that I'm developing at [Lugg](https://lugg.com).

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

[MIT](LICENSE)

---

Made with ❤️ by [@lodev09](http://linkedin.com/in/lodev09/)
