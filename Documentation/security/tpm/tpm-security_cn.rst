SPDX 许可证标识符: 仅 GPL-2.0

TPM 安全性
==========

本文档旨在描述我们如何使内核使用 TPM 在面对外部窥探和数据包篡改攻击时保持合理的健壮性（在文献中称为被动和主动中间人攻击）。当前的安全文档是针对 TPM 2.0 的。

简介
----

TPM 通常是一个通过某种低带宽总线连接到 PC 的独立芯片。也有一些例外，例如 Intel PTT，它是在接近 CPU 的软件环境中运行的软件 TPM，这会遭受不同的攻击。但就目前而言，大多数强化安全环境要求使用独立的硬件 TPM，这也是本文档讨论的用例。

针对总线的窥探与篡改攻击
------------------------------

目前最先进的窥探技术是 `TPM Genie`_ 硬件中间人设备，这是一种简单的外部设备，可以在几秒钟内在任何系统或笔记本电脑上安装。最近对 `Windows Bitlocker TPM`_ 系统成功进行了攻击。最近同样出现了针对基于 TPM 的 Linux 磁盘加密方案的 `攻击`_ 。下一阶段的研究似乎是破解总线上的现有设备以充当中间人，因此攻击者可能不再需要几秒钟的物理访问。然而，本文档的目标是在这种环境下尽可能保护 TPM 的机密性和完整性，并尝试确保即使无法阻止攻击也能至少检测到攻击。

不幸的是，大多数 TPM 功能，包括硬件重置功能，都可以被拥有总线访问权限的攻击者控制，因此下面将讨论一些可能的干扰方式。

度量（PCR）完整性
-------------------

由于攻击者可以向 TPM 发送自己的命令，他们可以发送任意的 PCR 扩展，从而破坏度量系统，这将是一种烦人的拒绝服务攻击。但是，有两类更严重的攻击针对依赖于信任度量的实体：

1. 攻击者可以拦截所有来自系统的 PCR 扩展并完全替换为自己的值，产生一个未受篡改状态的重放，这会导致 PCR 测量证明一个受信任的状态并释放秘密。

2. 在某个时间点，攻击者可以重置 TPM，清除 PCR 并然后发送自己的测量值，这实际上会覆盖 TPM 已经完成的启动时间测量。

第一种可以通过始终对 PCR 扩展和读取命令进行 HMAC 保护来防御，这意味着无法在不导致响应中的 HMAC 失败的情况下替换测量值。但是，第二种只能通过依赖某种机制来检测，该机制可以在 TPM 重置后发生变化。

守护机密
---------

进出 TPM 的某些信息，如密钥封存、私钥导入和随机数生成，容易受到拦截，HMAC 保护本身无法对此类信息提供保护，因此对于这些类型的命令，我们还必须采用请求和响应加密以防止机密信息丢失。

与 TPM 建立初始信任
---------------------

为了从一开始就提供安全性，必须建立一个初始共享或非对称秘密，这个秘密也必须为攻击者所不知。最明显的途径是认可种子和存储种子，它们可以用来派生非对称密钥。
然而，使用这些密钥是困难的，因为唯一传递它们到内核的方法是在命令行上进行，这需要启动系统中有大量的支持，并且无法保证这两个层级不会有任何形式的授权。
对于Linux内核选择的机制是从空种子（null seed）使用标准存储种子参数推导出主要椭圆曲线密钥。空种子有两个优点：首先，该层级物理上不可能有授权，所以我们总能使用它；其次，空种子在TPM重置时会改变，这意味着如果我们基于空种子建立信任，则所有使用推导密钥加盐的会话将在TPM重置且种子改变后失败。
显然，在没有任何其他共享秘密的情况下仅使用空种子，我们必须创建并读取初始公钥，这当然可能会被总线拦截器截获和替换。
然而，TPM有一个密钥认证机制（使用EK背书证书，生成证明身份密钥，并用该密钥认证空种子的主要密钥），这个机制过于复杂以至于不能在内核中运行，因此我们保留了一份空主密钥名称的副本，这就是通过sysfs导出的内容，以便用户空间在启动时可以运行完整的认证过程。这里确定性的保证是，如果空主密钥认证正确，你就知道自启动以来所有的TPM交易都是安全的；如果认证不成功，那么你知道系统上有拦截者存在（并且任何启动期间使用的秘密可能已被泄露）。

### 堆叠信任

在当前的空主密钥场景下，TPM必须在交给下一个消费者之前完全清除。然而，内核向用户空间传递的是由空种子推导出的密钥名称，然后可以在用户空间中通过认证来验证。因此，这种名称传递链可用于各个启动组件之间（通过某种未指定的机制）。例如，grub可以使用空种子方案来确保安全性，并将名称传递给位于启动区域的内核。内核可以自行推导密钥及其名称，并明确知道如果它们与传递过来的版本不同，则发生了篡改。这样就有可能将任意的启动组件（如UEFI到grub再到内核）通过名称传递链连接起来，只要每个后续组件知道如何收集名称并验证其与推导出的密钥相符。

### 会话属性

内核使用的所有TPM命令都允许会话。HMAC会话可用于检查请求和响应的完整性，而加密和解密标志可用于保护参数和响应。HMAC和加密密钥通常从共享授权秘密派生而来，但对于许多内核操作而言这是众所周知的（通常是空的）。因此，内核必须使用空主密钥作为加盐密钥来创建每一个HMAC会话，从而为会话密钥派生提供密码学输入。因此，内核一次性创建空主密钥（作为一个易失性TPM句柄），并将其保存在存储于tpm_chip中的上下文中，用于内核中的每一次TPM使用。目前，由于内核资源管理器缺乏脱节处理，会话必须为每个操作创建和销毁，但未来可能也会重用单一会话以供内核中的HMAC、加密和解密会话使用。

### 保护类型

对于内核中的每一次操作，我们都使用加盐的空主密钥HMAC来保护完整性。此外，我们还使用参数加密来保护密钥封存，并使用参数解密来保护密钥解封和随机数生成。

### 用户空间中的空主密钥认证

每个TPM都会附带一两个X.509证书用于主要背书密钥。本文档假设椭圆曲线版本的证书位于01C00002处，但同样适用于位于01C00001处的RSA证书。
认证的第一步是使用来自《TCG EK凭证配置文件》的模板创建主要密钥，这允许将生成的主要密钥与证书中的密钥（公钥必须匹配）进行比较。请注意，生成EK主要密钥需要EK层级密码，但是预生成的EC主要密钥应该存在于81010002处，并且可以在不需要密钥权限的情况下执行TPM2_ReadPublic()。接下来，必须验证证书本身以链接回制造商根证书（该证书应发布在制造商网站上）。一旦完成此步骤，就会在TPM内部生成一个证明密钥（AK），并使用其名称和EK公钥通过TPM2_MakeCredential加密一个秘密。然后TPM运行TPM2_ActivateCredential，只有当TPM、EK和AK之间的绑定真实时才会恢复秘密。现在可以使用生成的AK对内核导出的空主密钥进行认证。由于TPM2_MakeCredential/ActivateCredential过程较为复杂，下面描述了一个简化的过程，涉及外部生成的私钥。
这一过程是对通常基于隐私CA的证明过程的简化缩写。这里的假设是证明是由TPM所有者完成的，因此只有访问所有者层级的权限。所有者创建一个外部公私钥对（假设本例中使用椭圆曲线），并对私钥使用内部封装过程进行封装，并将其父级设置为EC衍生存储主密钥。使用参数解密HMAC会话对TPM2_Import()进行操作，该会话以EK主密钥加盐（这也无需EK密钥权限），这意味着内部封装密钥是加密的参数，因此除非TPM拥有经过认证的EK，否则它将无法执行导入操作。如果命令成功且返回时HMAC验证成功，我们知道我们有了仅针对经过认证的TPM可加载的私钥副本。此密钥现在被加载到TPM中，并将存储主密钥刷新（以腾出空间用于生成空密钥）。
空的EC主密钥现在是根据《TCG TPM v2.0 配置指导》_中概述的存储配置文件生成的；该密钥的名字（即公有区域的哈希值）被计算并与内核在/sys/class/tpm/tpm0/null_name中呈现的空种子名字进行比较。如果名字不匹配，则表示TPM已被破坏。如果名字匹配，用户使用空主密钥作为对象句柄、加载的私钥作为签名句柄，并提供随机化的限定数据来执行TPM2_Certify()操作。返回的certifyInfo的签名通过与加载私钥的公钥部分进行验证，并检查限定数据以防止重放攻击。如果所有这些测试都通过了，那么用户就可以确信，在这个内核的整个启动过程中TPM的完整性和隐私得到了保护。

.. _TPM Genie: https://www.nccgroup.trust/globalassets/about-us/us/documents/tpm-genie.pdf
.. _Windows Bitlocker TPM: https://dolosgroup.io/blog/2021/7/9/from-stolen-laptop-to-inside-the-company-network
.. _针对基于TPM的Linux磁盘加密的攻击: https://www.secura.com/blog/tpm-sniffing-attacks-against-non-bitlocker-targets
.. _TCG EK Credential Profile: https://trustedcomputinggroup.org/resource/tcg-ek-credential-profile-for-tpm-family-2-0/
.. _TCG TPM v2.0 配置指导: https://trustedcomputinggroup.org/resource/tcg-tpm-v2-0-provisioning-guidance/
