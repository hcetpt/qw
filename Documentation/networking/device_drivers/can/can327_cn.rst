### SPDX 许可证标识符：(GPL-2.0-only 或 BSD-3-Clause)

#### can327：用于 Linux SocketCAN 的 ELM327 驱动程序
==========================================

**作者**
--------

Max Staudt <max@enpas.org>



**动机**
-----------

该驱动程序旨在降低对 CAN 总线感兴趣的黑客的初始成本：
- CAN 适配器价格昂贵，选择有限。
- ELM327 接口便宜且广泛可用。
- 我们可以使用 ELM327 作为 CAN 适配器。

**介绍**
-------------

此驱动程序旨在将基于 ELM327 的 OBD 接口转变为功能完善的（尽可能地）CAN 接口。由于 ELM327 并非设计为独立的 CAN 控制器，因此驱动程序必须尽可能快地在不同模式间切换以模拟全双工操作。因此，can327 是一个尽力而为的驱动程序。然而，这对于实现简单的请求-响应协议（如 OBD II）和监控总线上的广播消息（如在车辆中）来说已经足够。大多数 ELM327 设备作为未明确标识的串行设备出现，通过 USB 或蓝牙连接。驱动程序本身无法识别这些设备，因此用户需要将其配置为 TTY 线律（类似于 PPP、SLIP、slcan 等）。此驱动程序适用于 ELM327 版本 1.4b 及以上版本，有关较旧控制器和克隆版的已知限制，请参见下文。

**数据手册**
--------------

官方数据手册可以在 ELM Electronics 的主页上找到：

  https://www.elmelectronics.com/



**如何附加线律**
-------------------

每个 ELM327 芯片出厂时都被编程为在以下串行设置下运行：38400 波特率，8 位数据位，无奇偶校验，1 位停止位。
如果你保留了默认配置，可以通过命令行来附加线路纪律如下：

    sudo ldattach \
           --debug \
           --speed 38400 \
           --eightbits \
           --noparity \
           --onestopbit \
           --iflag -ICRNL,INLCR,-IXOFF \
           30 \
           /dev/ttyUSB0

要更改ELM327的串行设置，请参考其数据手册。这需要在附加线路纪律之前完成。一旦线路纪律被附加，CAN接口将处于未配置状态。在启动前设置速度：

    # 接口需要处于关闭状态以改变参数
    sudo ip link set can0 down
    sudo ip link set can0 type can bitrate 500000
    sudo ip link set can0 up

500,000位/秒是OBD-II诊断中常见的速率。
如果你直接连接到汽车的OBD端口，这是大多数（但不是全部！）汽车期望的速度。
之后，你可以像往常一样使用candump、cansniffer等工具开始工作。
如何检查控制器版本
------------------------

使用终端程序连接到控制器。
发出"``AT WS``"命令后，控制器会回应其版本：

    >AT WS


    ELM327 v1.4b

    >

请注意，克隆产品可能声称自己是任何版本，这并不意味着它们的实际功能集。
通信示例
--------------

这是一个简短且不完整的介绍，关于如何与ELM327进行通信。
这里是为了帮助理解控制器和驱动器的限制（如下所述）以及手动测试。
ELM327有两种模式：

- 命令模式
- 接收模式

在命令模式下，它期望每行一个命令，并以回车符（CR）结束。
默认的提示符是“``>``”，之后可以输入命令：

    >ATE1
    OK
    >

驱动程序中的初始化脚本关闭了多个配置选项，这些选项仅在芯片设计用于的原始OBD场景中有意义，实际上对于can327来说是障碍。
当命令未被识别时，例如由ELM327的旧版本处理时，会打印一个问号作为响应而不是OK：

    >ATUNKNOWN
    ?
    >

目前，can327不会评估这个响应。有关已知限制的详细信息，请参阅下面的部分。
当需要发送CAN帧时，首先配置目标地址，然后将帧作为命令发送，该命令包含数据的十六进制转储：

    >ATSH123
    OK
    >DEADBEEF12345678
    OK
    >

上述交互发送了SFF帧“``DE AD BE EF 12 34 56 78``”，其CAN ID为``0x123``（11位）。
为了使此功能正常工作，控制器必须配置为SFF发送模式（使用"``AT PB``"，请参阅代码或数据手册）。
一旦发送了帧并且启用了等待回复模式（``ATR1``，在``listen-only=off``下配置），或者当回复超时期满且驱动程序将控制器设置为监控模式（``ATMA``）时，ELM327将为每个接收到的CAN帧发送一行，该行包含CAN ID、DLC和数据：

    123 8 DEADBEEF12345678

对于EFF（29位）CAN帧，地址格式略有不同，can327利用这一点来区分两种帧：

    12 34 56 78 8 DEADBEEF12345678

ELM327将接收SFF和EFF帧——当前的CAN配置（``ATPB``）无关紧要。
如果ELM327内部UART发送缓冲区满了，它将中断监控模式，打印“BUFFER FULL”并返回到命令模式。需要注意的是，在这种情况下，与其它错误消息不同，错误消息可能出现在同一行中（通常是不完整的）数据帧旁边：

    12 34 56 78 8 DEADBEEF123 BUFFER FULL


控制器的已知限制
--------------------

- 克隆设备（“v1.5”及其他）

  发送RTR帧不受支持，并会被静默丢弃。
接收带有DLC 8的RTR帧会表现为常规帧，具有最后一次接收帧的DLC和有效载荷。
"``AT CSM``"（CAN静默监控，即不发送CAN确认）不受支持，并且被硬编码为ON。因此，在监听时不会确认帧：“``AT MA``”（监控所有）始终处于“静默”状态。
然而，在发送帧后立即，ELM327将处于“接收回复”模式，在这种模式下，它确实会对接收到的任何帧进行确认。
一旦总线变得静默，或者发生错误（如 BUFFER FULL），或者接收回复超时，ELM327 将自动结束回复接收模式，并且 can327 会回退到 "``AT MA``" 模式以继续监控总线。
其他限制可能适用，这取决于克隆版本及其固件的质量。
- 所有版本

  不支持全双工操作。驱动程序将尽可能快地在输入/输出模式之间切换。
无法设置发出的 RTR 帧的长度。实际上，某些克隆版本（已在一个自识别为 "``v1.5``" 的设备上测试）根本无法发送 RTR 帧。
我们没有获取 CAN 错误实时通知的方法。
虽然有一个命令（``AT CS``）可以检索一些基本统计信息，但我们不会轮询它，因为这样做会迫使我们中断接收模式。
- 1.4b 版本之前

  这些版本在监控模式（AT MA）下不发送 CAN 确认应答（ACK）。
然而，在发送帧后立即等待回复时，它们确实发送确认应答。驱动程序最大化了这段时间以使控制器尽可能有用。
从 1.4b 版本开始，ELM327 支持 "``AT CSM``" 命令，并且“仅监听”CAN 选项将生效。
- 1.4 版本之前

  这些芯片不支持 "``AT PB``" 命令，因此不能动态更改比特率或 SFF/EFF 模式。这需要用户在连接线路规程前进行编程。具体细节请参阅数据手册。
版本 1.3 之前的版本

这些芯片完全不能与 can327 一起使用。它们不支持 `"AT D1"` 命令，该命令对于避免解析传入数据时的冲突以及区分远程传输请求 (RTR) 帧长度是必要的。
特别是，这允许轻松地区分标准格式 (SFF) 和扩展格式 (EFF) 帧，并检查帧是否完整。虽然可以从 ELM327 发送给我们的行的长度推断出类型和长度，但当 ELM327 的 UART 输出缓冲区溢出时，这种方法会失败。它可能会在一行的中间中断发送，这将被错误地识别为其他内容。

已知的驱动程序限制
----------------------

- 不支持 8/7 定时
ELM327 只能设置形式为 500000/n 的 CAN 波特率，其中 n 是整数除数。
但是有一个例外：通过一个单独的标志，它可以将速度设置为由除数指示的速度的 8/7 倍。
这种模式目前尚未实现。
- 不评估命令响应
当 ELM327 理解命令时，它会回复 "OK"；当它不理解命令时，则回复 "?"。当前驱动程序不检查这一点，而是简单地假设芯片能够理解所有命令。
驱动程序的设计方式确保了即使存在这些问题，功能也能优雅地降级。请参阅控制器的已知限制部分。
- 不使用硬件 CAN ID 过滤器

在 CAN 总线负载较重的情况下，ELM327 的 UART 发送缓冲区很容易溢出，从而导致出现 "BUFFER FULL" 消息。通过 `"AT CF xxx"` 和 `"AT CM xxx"` 使用硬件过滤器在这种情况下是有帮助的，然而 SocketCAN 目前没有提供利用此类硬件特性的功能。
所选配置的理由
-----------------------------------

``AT E1``
  开启回显

  我们需要这样设置以便可靠地获取提示符。
``AT S1``
  开启空格

  我们需要这样设置来区分接收到的 11/29 位 CAN 地址。
注：
  通常我们可以使用行长度（奇数/偶数）来实现这一点，
  但如果数据没有完全传输到主机（缓冲区满），这种方法就会失败。
``AT D1``
  DLC 开启

  我们需要这样设置来判断远程传输请求 (RTR) 帧的“长度”。

关于 CAN 总线终端电阻的说明
------------------------------

您的适配器可能焊有用于总线终端的电阻。当适配器插在 OBD-II 插座中时，这种做法是正确的，但在尝试接入现有的 CAN 总线中间时则不适用。
如果连接适配器后通信无法正常工作，请检查适配器电路板上的终端电阻，并尝试移除它们。
