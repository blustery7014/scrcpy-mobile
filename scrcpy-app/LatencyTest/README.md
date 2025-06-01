# LatencyTest

网络延时测试工具集，提供TCP连接延时和ADB协议延时测量功能。

## 目录结构

```
LatencyTest/
├── README.md                      # 本文件 - 总体介绍
├── TCPLatencyTester.h             # TCPLatencyTester 类头文件
├── TCPLatencyTester.m             # TCPLatencyTester 类实现
├── TCPLatencyTester_README.md     # TCPLatencyTester 详细文档
├── TCPLatencyTester_Example.m     # TCPLatencyTester 使用示例
├── ADBLatencyTester.h             # ADBLatencyTester 类头文件
├── ADBLatencyTester.m             # ADBLatencyTester 类实现
├── tcp-latency-tester-cli.m       # TCP延时测试命令行工具源码
├── tcp-latency-tester             # 编译后的TCP测试可执行文件
└── Makefile                       # 编译配置
```

## 测试工具介绍

### TCPLatencyTester
- **用途**: 测试任意TCP端口的连接延时
- **方法**: TCP握手 + 数据包收发
- **适用**: VNC连接、HTTP服务器、通用TCP服务

### ADBLatencyTester  
- **用途**: 测试ADB协议连接延时
- **方法**: ADB CNXN握手协议
- **适用**: Android设备ADB连接

## 快速开始

### 1. 编译

```bash
cd LatencyTest
make
```

### 2. 使用命令行工具

```bash
# TCP延时测试
./tcp-latency-tester google.com 80

# 多次测试求平均
./tcp-latency-tester 8.8.8.8 53 -c 5

# 查看帮助
./tcp-latency-tester --help
```

### 3. 在代码中使用

#### TCP延时测试
```objc
#import "TCPLatencyTester.h"

TCPLatencyTester *tester = [[TCPLatencyTester alloc] initWithHost:@"example.com" portNumber:80];
[tester testLatency:^(NSNumber *latencyMs, NSError *error) {
    if (error) {
        NSLog(@"测试失败: %@", error.localizedDescription);
    } else {
        NSLog(@"TCP延时: %.2f ms", [latencyMs doubleValue]);
    }
}];
```

#### ADB延时测试
```objc
#import "ADBLatencyTester.h"

NSDictionary *session = @{
    @"hostReal": @"192.168.1.100",
    @"port": @"5555",
    @"deviceType": @"adb"
};

ADBLatencyTester *tester = [[ADBLatencyTester alloc] initWithSession:session];
[tester testLatency:^(NSNumber *latencyMs, NSError *error) {
    if (error) {
        NSLog(@"测试失败: %@", error.localizedDescription);
    } else {
        NSLog(@"ADB延时: %.2f ms", [latencyMs doubleValue]);
    }
}];
```

## 主要功能

- **多协议支持** - 支持TCP通用测试和ADB专用测试
- **异步执行** - 不阻塞主线程
- **自定义数据包** - 支持发送自定义内容（TCP测试）
- **多次测试平均** - 支持多次测试计算平均值
- **可配置超时** - 支持设置连接和读取超时
- **详细日志** - 提供调试信息和错误处理
- **命令行工具** - 独立的CLI工具

## 文件说明

### 核心类库
- **TCPLatencyTester.h/m** - 通用TCP延时测试类
- **ADBLatencyTester.h/m** - ADB协议专用延时测试类
- **TCPLatencyTester_README.md** - TCP测试详细文档

### 工具和示例
- **tcp-latency-tester-cli.m** - TCP测试命令行工具源码
- **TCPLatencyTester_Example.m** - 编程接口使用示例
- **Makefile** - 编译配置文件

### 编译产物
- **tcp-latency-tester** - 编译后的TCP测试命令行工具

## 编译命令

```bash
make           # 编译
make clean     # 清理
make install   # 安装到系统
make test      # 运行测试
make help      # 查看帮助
```

## 应用场景

### 根据连接类型自动选择测试方法
在Scrcpy Remote应用中，会根据session类型自动选择合适的延时测试方法：

- **ADB设备** (`deviceType == .adb`) - 使用 `ADBLatencyTester`
- **VNC设备** (`deviceType == .vnc`) - 使用 `TCPLatencyTester`

这样可以确保：
- ADB连接获得更准确的协议层延时
- VNC连接获得纯TCP连接延时
- 不同类型设备的延时数据具有可比性

## 常见用例

1. **网络质量检测** - 测试到特定服务器的延时
2. **ADB设备连接质量** - 测试到Android设备的ADB协议延时  
3. **VNC服务器连接** - 测试到VNC服务器的TCP延时
4. **服务器健康检查** - 定期检测服务器响应时间
5. **网络故障诊断** - 识别网络连接问题
6. **性能监控** - 监控网络延时变化

## 技术特点

- 使用低级BSD socket API确保精确测量
- ADB协议层面的真实握手测试
- 支持DNS解析和IP地址连接
- 完整的错误处理和超时控制
- 内存安全的Objective-C实现
- 跨平台兼容（macOS/iOS） 