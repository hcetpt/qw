### SPDX 许可证标识符：GPL-2.0
### _representors_：

=============================
网络功能表示器
=============================

本文档描述了用于控制SmartNIC内部交换的表示器网卡（representor netdevices）的语义和用法。对于与之紧密相关的物理（多端口）交换机上的端口表示器，请参阅[Documentation/networking/switchdev.rst](<switchdev>)。
#### 动机
----------

自2010年代中期以来，网络适配卡开始提供比传统的SR-IOV方法（基于简单的MAC/VLAN交换模型）更为复杂的虚拟化能力。这导致了将软件定义网络（如OpenVSwitch）卸载到这些NIC上以指定每个功能的网络连接性的需求。由此产生的设计被称作SmartNIC或DPUs。

网络功能表示器为虚拟交换机和IOV设备带来了标准的Linux网络堆栈。就像Linux控制的交换机的每个物理端口都有一个独立的netdev一样，虚拟交换机的每个虚拟端口也有一个。

在系统启动时，在任何卸载配置之前，所有来自虚拟功能的数据包都会通过表示器出现在PF的网络堆栈中。因此，PF始终可以自由地与虚拟功能进行通信。

PF可以配置标准Linux转发规则在表示器之间、上行链路或其他任何netdev之间（路由、桥接、TC分类器等）。

因此，表示器既是控制平面对象（在管理命令中代表功能）也是数据平面对象（虚拟管道的一端）。

作为虚拟链路的终点，表示器可以像其他任何netdevice一样进行配置；在某些情况下（例如，链路状态），被表示者（representee）会跟随表示器的配置，而在其他情况下则有单独的API来配置被表示者。
#### 定义
----------

本文档使用术语“switchdev功能”来指代设备上具有对设备上的虚拟交换机进行管理控制的PCIe功能。

通常，这将是PF（物理功能），但理论上NIC也可以配置为将这些管理权限授予VF（虚拟功能）或SF（子功能）。

根据NIC的设计，一个多端口NIC可能为整个设备有一个单一的switchdev功能，或者为每个物理网络端口都有一个独立的虚拟交换机，从而也有一个独立的switchdev功能。
如果网卡支持嵌套交换，那么对于每个嵌套交换机可能有单独的`switchdev`函数，在这种情况下，每个`switchdev`函数只应为它直接管理的（子）交换机上的端口创建代表者（representor）。

“被代表者”（representee）是代表者所代表的对象。例如，在VF代表者的案例中，被代表者就是对应的VF。

代表者的作用是什么？
------------------------

代表者主要有三个作用：
1. 用于配置被代表者看到的网络连接，例如链路上下、MTU等。例如，将代表者设置为UP状态应使被代表者检测到链路上事件/载波。
2. 提供未命中虚拟交换机中的快速路径规则的数据包的慢路径。在代表者网络设备上发送的数据包应传递给被代表者；被代表者发送的未匹配任何交换规则的数据包应在代表者网络设备上接收。（也就是说，存在一个虚拟管道连接代表者和被代表者，类似于veth对的概念。）
   这允许软件交换实现（如OpenVSwitch或Linux桥接器）转发数据包在被代表者与网络其余部分之间。
3. 作为切换规则（如TC过滤器）引用被代表者的句柄，使这些规则可以卸载。

第2点和第3点的结合意味着，无论TC过滤器是否卸载，其行为（除了性能外）应该是相同的。例如，一个TC规则在VF代表者上应用于该代表者网络设备接收到的数据包，而在硬件卸载时，它会应用于被代表者VF发送的数据包。相反地，镜像出口重定向到VF代表者在硬件上对应于直接交付给被代表者VF。

哪些功能应该有一个代表者？
--------------------------------

原则上，对于设备内部交换机上的每个虚拟端口，都应该有一个代表者。
一些供应商选择不为上行链路和物理网络端口提供代表者，这可以简化使用（上行链路网络设备实际上成为物理端口的代表者），但这并不适用于具有多个端口或上行链路的设备。
因此，以下各项都应当拥有代表接口（representor）：

- 属于交换设备功能的虚拟功能（VFs）
- 本地 PCIe 控制器上的其他物理功能（PFs），以及属于它们的任何虚拟功能（VFs）
- 设备上外部 PCIe 控制器上的物理功能（PFs）和虚拟功能（VFs）（例如，在智能网络接口卡(SmartNIC)中嵌入的任何系统级芯片(System-on-Chip)）
- 具有其他特性的物理功能（PFs）和虚拟功能（VFs），包括网络块设备（如通过远程/分布式存储支持的 vDPA virtio-blk 物理功能(PF)），但前提是（且仅当是）其网络访问是通过虚拟交换机端口实现的。[#]_需要注意的是，即使被代表的接口没有网卡设备（netdev），这样的功能也可能需要一个代表接口。
- 如果上述物理功能（PFs）或虚拟功能（VFs）的子功能（SFs）有自己的交换机端口（而不是使用其父物理功能(PF)的端口），那么这些子功能也应拥有代表接口。
- 设备上的任何加速器或插件，如果它们通过虚拟交换机端口与网络进行交互，即使它们没有对应的 PCIe 物理功能(PF)或虚拟功能(VF)，也应该拥有代表接口。

这样可以确保整个网络接口卡(NIC)的交换行为可以通过代表接口的 TC 规则来控制。

通常会误解虚拟端口与 PCIe 虚拟功能及其网卡设备之间的关系。虽然在简单情况下，VF 网卡设备与 VF 的代表接口之间可能存在一对一的对应关系，但在更复杂的设备配置中可能并不遵循这一规律。

如果一个 PCIe 功能不通过内部交换机进行网络访问（即使是间接地通过该功能所提供的服务的硬件实现），则不应为其分配代表接口（即使它有一个网卡设备）。

这样的功能没有可供代表接口配置的交换机虚拟端口，也没有作为虚拟管道另一端的对象。
### 代表端口代表的是虚拟端口，而不是PCIe功能或“最终用户”的网络设备。
1. 这里的概念是设备中的硬件IP堆栈执行块DMA请求与网络数据包之间的转换，因此只有网络数据包通过虚拟端口传输到交换机上。IP堆栈所“看到”的网络访问可以通过tc规则进行配置；例如，其流量可能全部被封装在一个特定的VLAN或VxLAN中。然而，对于块设备作为块设备本身所需的任何配置（不是网络实体），不适合在代表端口中进行，因此会使用其他通道，如devlink。

与之形成对比的是，在virtio-blk实现中，将DMA请求原样转发给另一个PF，该PF的驱动程序随后在软件中启动和终止IP流量；在这种情况下，DMA流量不会经过虚拟交换机，因此virtio-blk PF不应该有代表端口。

### 代表端口是如何创建的？

连接到switchdev功能的驱动实例应该为交换机上的每个虚拟端口创建一个纯软件的网络设备，该设备在内核中有某种形式的对switchdev功能自身网络设备或驱动程序私有数据(``netdev_priv()``)的引用。

这可能是通过在探测时枚举端口、动态响应运行时端口的创建和销毁，或是这两种方式的组合来完成。

代表端口网络设备的操作通常会通过switchdev功能来执行。例如，``ndo_start_xmit()``可能会通过与switchdev功能关联的硬件TX队列发送数据包，并通过数据包元数据或队列配置将其标记为要传送给被代表者。

### 代表端口是如何标识的？

代表端口网络设备不应直接引用PCIe设备（例如通过``net_dev->dev.parent`` / ``SET_NETDEV_DEV()``），无论是被代表者的还是switchdev功能的。

相反，驱动程序应使用``SET_NETDEV_DEVLINK_PORT``宏在注册网络设备之前为网络设备分配一个devlink端口实例；内核使用devlink端口提供``phys_switch_id``和``phys_port_name`` sysfs节点。

（一些遗留驱动程序直接实现了``ndo_get_port_parent_id()``和``ndo_get_phys_port_name()``，但这种方式已被弃用。）关于此API的详细信息，请参阅：:ref:`Documentation/networking/devlink/devlink-port.rst <devlink_port>`。
预计用户空间会使用这些信息（例如通过 udev 规则）
来为网络设备构建一个适当且具有信息性的名称或别名。例如，如果交换机设备的功能是“eth4”，那么一个具有“phys_port_name”为“p0pf1vf2”的代表器（representor）可能会被重命名为“eth4pf1vf2rep”。
目前对于那些不对应于 PCIe 功能的代表器（例如加速器和插件）还没有建立命名规范。
代表器如何与 TC 规则交互？
-------------------------------------------

任何在代表器上的 TC 规则（在软件 TC 中）都适用于该代表器网络设备接收到的数据包。因此，如果规则的传递部分对应虚拟交换机上的另一个端口，驱动程序可以选择将其卸载到硬件中，将规则应用于由该代表器所代表的设备传输的数据包。
类似地，由于针对代表器的 TC 的镜像出口操作（mirred egress）会在软件中将数据包发送过代表器（间接地将数据包传递给被代表的设备），硬件卸载应该解释为传递给被代表的设备。
作为一个简单的例子，假设“PORT_DEV”是物理端口的代表器而“REP_DEV”是一个虚拟功能（VF）的代表器，以下规则：

    tc filter add dev $REP_DEV parent ffff: protocol ipv4 flower \
        action mirred egress redirect dev $PORT_DEV
    tc filter add dev $PORT_DEV parent ffff: protocol ipv4 flower skip_sw \
        action mirred egress mirror dev $REP_DEV

意味着所有来自虚拟功能的 IPv4 数据包都会通过物理端口发送出去，并且所有在物理端口上接收的 IPv4 数据包除了被“PORT_DEV”处理外还会被传递给虚拟功能。注意如果没有在第二个规则中使用“skip_sw”，虚拟功能会收到两份副本，因为“PORT_DEV”上的数据包接收会再次触发 TC 规则并镜像数据包至“REP_DEV”。

在没有单独端口和上行链路代表器的设备上，“PORT_DEV”将是交换机设备自身的上行链路网络设备。
当然，如果网卡支持的话，规则可以包括修改数据包的操作（例如 VLAN 推送/弹出），这些操作应由虚拟交换机执行。
隧道封装和解封装要复杂得多，因为它涉及到第三个网络设备（一个以元数据模式运行的隧道网络设备，如使用 `ip link add vxlan0 type vxlan external` 创建的 VxLAN 设备），并且需要绑定一个 IP 地址到底层设备（例如，交换机设备的上行链路网络设备或端口代表器）。像下面这样的 TC 规则：

    tc filter add dev $REP_DEV parent ffff: flower \
        action tunnel_key set id $VNI src_ip $LOCAL_IP dst_ip $REMOTE_IP \
                              dst_port 4789 \
        action mirred egress redirect dev vxlan0
    tc filter add dev vxlan0 parent ffff: flower enc_src_ip $REMOTE_IP \
        enc_dst_ip $LOCAL_IP enc_key_id $VNI enc_dst_port 4789 \
        action tunnel_key unset action mirred egress redirect dev $REP_DEV

其中“LOCAL_IP”是绑定到“PORT_DEV”的一个 IP 地址，而“REMOTE_IP”是同一子网上的另一个 IP 地址，这意味着虚拟功能发送的数据包应该被 VxLAN 封装并通过物理端口发送（驱动程序需要通过查找“LOCAL_IP”的路由来推断出“PORT_DEV”，同时还需要进行 ARP/邻居表查找来确定外层以太网帧使用的 MAC 地址），而 UDP 数据包在物理端口上接收且 UDP 端口为 4789 的话，则应该被解析为 VxLAN 并且如果它们的 VSID 匹配“$VNI”，则解封装并转发给虚拟功能。
如果这一切看起来很复杂，请记住 TC 卸载的“黄金法则”：硬件应确保与数据包通过慢路径、经过软件 TC（忽略任何“skip_hw”规则并应用任何“skip_sw”规则）以及通过代表器网络设备收发相同的结果。
配置被代表设备的 MAC 地址
---------------------------------

被代表设备的链接状态由代表器控制。将代表器设置为管理上或下的状态应该导致被代表设备的载波状态为开启或关闭。
在代表器上设置的最大传输单元（MTU）应该导致相同的 MTU 被报告给被代表设备。
（在允许配置独立且不同的MTU和MRU值的硬件上，
代理接口的MTU应与被代理接口的MRU相对应，反之亦然。）

目前没有方法使用代理接口来设置被代理接口的永久MAC地址；可以采用的其他方法包括：

 - 传统的SR-IOV（``ip link set DEVICE vf NUM mac LLADDR``）
 - devlink端口功能（参见**devlink-port(8)** 和
   :ref:`Documentation/networking/devlink/devlink-port.rst <devlink_port>`）
