import argparse

def main():
    parser = argparse.ArgumentParser(description="原生构建辅助脚本（纯 Dart 引擎免编译）")
    parser.add_argument('--platform', choices=['android', 'windows', 'darwin'], required=False)
    parser.add_argument('--abi', action='append', choices=['arm64-v8a', 'armeabi-v7a', 'x86_64'])
    print("本项目采用纯 Dart 核心调度引擎与 CatPawOpen JS 运行时沙箱，全平台开箱即用，构建无需预先生成动态库。")

if __name__ == '__main__':
    main()
