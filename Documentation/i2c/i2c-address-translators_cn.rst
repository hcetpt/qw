SPDX 许可证标识符: GPL-2.0

=======================
I2C 地址转换器
=======================

作者: Luca Ceresoli <luca@lucaceresoli.net>
作者: Tomi Valkeinen <tomi.valkeinen@ideasonboard.com>

描述
-----------

I2C 地址转换器 (ATR) 是一种设备，它有一个 I2C 从属父端口（"上游"）和 N 个 I2C 主控子端口（"下游"），并将交易从上游转发到合适的下游端口，并修改从属地址。在父总线上使用的地址被称为“别名”，并且可能与子总线的物理从属地址不同。地址转换由硬件完成。
ATR 类似于一个 i2c-mux，除了：
 - 父总线和子总线上的地址可以不同
 - 通常不需要选择子端口；在父总线上使用的别名意味着选择了该端口

ATR 功能可以由具有许多其他特性的芯片提供
内核中的 i2c-atr 提供了一个辅助函数来实现在驱动程序中的 ATR
ATR 在每个子总线上创建一个新的 I2C "子"适配器。在子总线上添加设备最终会调用驱动程序代码来选择一个可用的别名。维护一个适当的可用别名池并为每个新设备挑选一个别名取决于驱动程序开发者。ATR 维护一个当前分配别名的表，并使用它来修改所有指向子总线上设备的 I2C 交易
以下是一个典型的例子
拓扑结构如下：

                      从属 X @ 0x10
              .-----.   |
  .-----.     |     |---+---- B
  | CPU |--A--| ATR |
  `-----'     |     |---+---- C
              `-----'   |
                      从属 Y @ 0x10

别名表：

A、B 和 C 是三个物理 I2C 总线，在电气上是相互独立的。ATR 接收在总线 A 上发起的交易，并根据交易中的设备地址以及基于别名表将它们传播到总线 B 或总线 C 或者都不传播
别名表：

.. 表格::

   ===============   =====
   客户端            别名
   ===============   =====
   X (总线 B, 0x10)   0x20
   Y (总线 C, 0x10)   0x30
   ===============   =====

交易流程：

 - 从属 X 驱动请求一个交易（通过适配器 B），从属地址 0x10
 - ATR 驱动发现从属 X 在总线 B 上且别名为 0x20，重写消息地址为 0x20 并转发给适配器 A
 - 物理 I2C 交易在总线 A 上，从属地址 0x20
 - ATR 芯片检测到地址为 0x20 的交易，找到它在表中，将交易传播到总线 B 并将地址转换为 0x10，并保持总线 A 上时钟拉伸等待回复
 - 从属 X 芯片（在总线 B 上）检测到交易在其自身的物理地址 0x10 并正常回复
 - ATR 芯片停止时钟拉伸并转发回复到总线 A，将地址转换回 0x20
 - ATR 驱动接收到回复，重写消息地址为 0x10 以恢复初始状态
 - 从属 X 驱动获得 msgs[]，包括回复和地址 0x10

使用方法：

 1. 在驱动程序中（通常在 probe 函数中）通过调用 i2c_atr_new() 添加一个 ATR，传递 attach/detach 回调函数
 2. 当 attach 回调被调用时，选择一个合适的别名，在芯片中配置它，并在 alias_id 参数中返回所选的别名
 3. 当 detach 回调被调用时，从芯片中取消配置别名，并将别名放回池中以备后用

I2C ATR 函数和数据结构
-------------------------------------

.. kernel-doc:: include/linux/i2c-atr.h
