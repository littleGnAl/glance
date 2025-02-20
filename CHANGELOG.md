# CHANGELOG

## [0.6.0](https://github.com/littleGnAl/glance/compare/0.5.0...0.6.0) (2025-02-20)

## [0.5.0](https://github.com/littleGnAl/glance/compare/0.4.0...0.5.0) (2024-10-18)

### Changes

* Updates minimum supported SDK version to Flutter 3.10/Dart 3.0 ([#58](https://github.com/littleGnAl/glance/issues/58)) ([b1f37ba](https://github.com/littleGnAl/glance/commit/b1f37ba058b7f6e4aa9ea0ecbcfb1381c2fefb3e))

## [0.4.0](https://github.com/littleGnAl/glance/compare/0.3.0...0.4.0) (2024-10-17)

### Changes

* Optimize memory usage for stack capture ([#50](https://github.com/littleGnAl/glance/issues/50)) ([cb98944](https://github.com/littleGnAl/glance/commit/cb98944fc4b3a18fd1383b96a0fe5976c6f30452))
* support android 15 16k page size ([#49](https://github.com/littleGnAl/glance/issues/49)) ([228a197](https://github.com/littleGnAl/glance/commit/228a197904b1c4460cbe57e95ebd225e1b603775))

## [0.3.0](https://github.com/littleGnAl/glance/compare/0.2.0...0.3.0) (2024-10-01)


### ⚠ BREAKING CHANGES

* Remove `GlanceConfiguration.modulePathFilters` and optimize the performance of `aggregateStacks` (#38)

### Changes

* Implement GlanceNoOpImpl in debug mode ([#39](https://github.com/littleGnAl/glance/issues/39)) ([f9728a6](https://github.com/littleGnAl/glance/commit/f9728a65e2326df26099860a94616a101eb2efa7))
* Remove `GlanceConfiguration.modulePathFilters` and optimize the performance of `aggregateStacks` ([#38](https://github.com/littleGnAl/glance/issues/38)) ([facf5d7](https://github.com/littleGnAl/glance/commit/facf5d7aa745d73c1250942ac670fd14b57c73ea))
* Remove GlanceStackTrace interface and reuse the StackTrace interface of Dart SDK ([#35](https://github.com/littleGnAl/glance/issues/35)) ([1129af8](https://github.com/littleGnAl/glance/commit/1129af88bb5ad722b971dd4543f5d7e048c150ea))

## [0.2.0](https://github.com/littleGnAl/glance/compare/0.1.0...0.2.0) (2024-09-25)

* Refactored unwind logic
* Optimized stack trace aggregation logic

## 0.1.0

* Initial release.
