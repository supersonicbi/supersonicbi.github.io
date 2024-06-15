+++
title = "设计思路"
description = ""
weight = 2
+++

通过自然语言界面（Natural Language Interface）访问数据是数据库上古大神们就开始畅想的情境，在学术界也一直是专门的研究方向。对我们影响比较大的两篇论文是IBM在2016年发表的[ATHENA](http://www.vldb.org/pvldb/vol9/p1209-saha.pdf)和谷歌在2017年发表的[Analyza](https://static.googleusercontent.com/media/research.google.com/zh-CN//pubs/archive/45791.pdf)，但它是纯基于规则的工程实现。2017年之后，随着大规模数据集[Seq2SQL](https://arxiv.org/pdf/1709.00103.pdf)和[Spider](https://aclanthology.org/D18-1425.pdf)发布，基于AI模型的解决方案如雨后春笋般涌现，从seq2seq到slot filling，从schema linking到intermediate representation，各种奇淫技巧不一而足。直到ChatGPT横空出世，基于prompting来实现Text-to-SQL几乎成了大家的共识。

在项目初期，我们也曾尝试通过prompt engineering让ChatGPT直接生成SQL，但经过多轮迭代，在稳定性和可靠性方面始终无法达到生产可用的期望，总的来说有如下问题：

**语义复杂**
- 如果涉及多表关联、运算公式、时间转换等复杂语义情况，SQL生成难度变高，LLM输出可靠性会显著降低。
- 涉及指标计算的场景，如果依赖用户问询来描述，无法保证口径的一致性与确定性。

**输出幻觉**

- 为了让LLM理解schema，需要将所有字段的名称和描述作为context输入，如果schema字段数量多，可能会超过context window限制。因此，基数过大的字段取值一般不会全部放入context，使得LLM无法识别到专有领域的术语。即便将schema全部输入且告知LLM不要随意猜测，仍然有一定几率会预测出错误的字段，甚至可能幻觉出不存在的字段。
- 相同的语义，不同的语言表达，可能会导致大相径庭的输出结果，无法保证一致性。

**推理效率**

- 当前LLM推理速度还处在10秒+量级，再加上底层数据查询的耗时，同时还无法像纯文本那样的流式输出，非常考验用户的耐心。
- 当前LLM主流是按token计费，如果所有查询都需要走LLM，MaaS成本会随着查询量线性增长。

我们逐渐意识到，LLM只是看作是意图识别和文本生成的引擎，它还需要其他的组件来配套，才构成一个完整的系统解决方案。可与此类比的是传统OLAP引擎，需要有transformation层的清洗、关联、聚合等建模步骤来配套，才能形成高效稳定的数据服务。

因此，在SuperSonic项目中我们围绕LLM引入与之配套的工程化组件，来增强语义解析和SQL生成的可靠性。架构图里黄色背景块就是引入的配套组件，下面的篇幅将展开介绍设计思考。

<img alt="supersonic_components" src="https://github.com/tencentmusic/supersonic/assets/3949293/23b396c2-d832-430e-936d-0a23b4085aea" height="50%" width="50%" >

### Semantic Layer

当AI领域的LLM满级输出吸走大部份聚光灯的时候，BI领域也有一位召唤师在猥琐发育——它就是Semantic Layer（也有称为是Headless BI或者Metric Store）。所以它的核心价值是什么？我们可以用两个拟人化的角色来类比：

- **翻译官**：将技术名词（表/字段）翻译成业务术语（维度/指标/标签），便于业务用户理解。
- **大管家**：将技术口径（关联关系/运算公式）统一化、精细化地管理起来，便于查帐比对，消除口径混乱。

两类角色的存在都可以提升数据服务质量，增强业务对数据的理解和信任。而随着企业内数据规模和使用场景的不断扩展，对于数据的组织能力和传播能力越来越成为数据驱动落地的关键因素（这似乎跟企业本身的发展是一个道理），所以semantic layer得到越来越多的关注与认可。

接下来的问题，semantic layer和LLM又有什么联系？我们还是从它的两类角色上来分析：

- 翻译官将技术名词翻译成更有意义的业务术语，便于业务用户理解的同时，同样能增强LLM对数据的语义理解。
- 大管家将技术口径封装起来，LLM不需要考虑关联关系和运算公式，生成复杂度极大地被简化。

因此，既然semantic layer可以帮助人更好地把数据用起来，为什么不顺便帮一下LLM，举手之劳而已。

### Schema Mapper

前文有提到LLM的token限制问题，主要是因为想要暴力求解，将全部字段的名称和取值一股脑都丢给LLM。直观分析，可以在前置环节增加**映射机制**，只保留能在输入文本中映射上的字段，可以极大地减少token使用，即便不超过限制，也能节省推理成本。这就是Schema Mapper组件的由来。

当前的设计方案是，定期从semantic model中抽取名称、别名、取值来构建词典，形成内部的knowledge base。查询解析阶段，先对输入文本分词，再采用n-gram词典探测的机制。经过前期调研，中文NLP框架[HanLP](https://github.com/hankcs/HanLP)相对成熟，可以满足需要。

Schema mapper会将所有达到匹配阈值要求的schema项及其相似度得分一并保存到info对象，传递给后续semantic parsing环节引用，最终会由parser挑选输入给LLM。

与此同时，schema mapper可以定制扩展，并通过Java SPI配置的方式替换或补充SuperSonic的默认实现。

### Semantic Corrector

针对前文提到的推测错误和幻觉问题，一个方向是对prompt不断试验打磨，但现阶段仍然是玄学成分居多。另一个方向是，在LLM输出的后置环节增加**修正机制**，将明显错误的表达予以修复。这就是Semantic Corrector组件的由来。

当前的设计方案是，从LLM生成的SQL中解析出表、字段、取值等名词，逐个检查合法性，将不合法名词通过类似schema mapping的方式去knowledge base尝试找到正确的匹配。比如，LLM可能将取值映射到了错误的字段，通过corrector尝试找到正确的字段映射，并改写SQL。

与此同时，semantic corrector可以定制扩展，并通过Java SPI配置的方式替换或补充SuperSonic的默认实现。

### Rule-based Parser

针对前文提到的效率问题，除了做时间的朋友，等待LLM进化突破之外，还可以想办法在应用层规避。比如，对于一些简单的问题输入，可以尝试基于规则来做语义解析，这也是从Google Analyza论文里带来的启发。这就是Rule-based Parser的由来。

当前的设计方案是，通过经验整理一份表单，如下表所示，明确列举每类语义对象（指标/维度/取值/时间/算子）的组合会映射到哪一种查询意图。Rule-based parser再根据schema mapping的结果，从表单中查到对应的查询意图，这个有点类似slot filling的思路。

<img width="1630" alt="rule-based parser slot-filling" src="https://github.com/tencentmusic/supersonic/assets/3949293/1df91461-6f09-45c5-bde0-607deab28a10">

引入Semantic Parser的抽象，分别有rule-based和LLM-based的实现。输入问题首先经过rule-based parser，如果有查询意图命中，则根据启发性算法来决定是否可以跳过LLM-based parser。当前，启发性算法会根据schema mapping命中的词汇总长度除以问题总长度来判断，超过配置的阈值则认为规则可以满足需要，决定跳过LLM，如果跳过那么提升效率的目的就达到了。

与此同时，semantic parser可以定制扩展，并通过Java SPI配置的方式替换或补充SuperSonic的默认实现，也可以选择完全去掉rule-based parser配置。

### Chat Plugin

SuperSonic的主链路主要涉及两个步骤：1、LLM解析语义，生成逻辑SQL，提交semantic layer；2、semantic layer生成物理SQL，提交底层OLAP引擎执行。但是，既然已经有了统一的ChatBI界面，是否能兼容其他的场景，比如文档知识库、数据看板，它们的执行过程不同于SuperSonic主链路。这就是Chat Plugin组件的由来。

当前的设计方案是，三方插件可以通过WebPage（将直接IFrame嵌入展现）或者WebService（HTTP调用获取返回）两种方式来注册，后续会当作是一种工具来使用。当用户输入问题时，如何选择出合适的插件工具？经典的方式有以下两种：

- **向量召回**：插件在注册时可以设定一些示例问题，提前通过LLM向量化存储到向量数据库。解析输入问题时，将输入文本同样经过LLM向量化后，从向量数据库根据相似度来召回，通过最匹配的示例问题找到相对应的插件；
- **函数调用**：插件在注册时可以配置函数名称和描述，利用LLM的function call能力来直接根据输入问题选择函数，并找到对应的插件。

两种方式可以结合使用，优先走向量召回流程，如果相似度没有达到配置的阈值，则继续用函数调用来选择。


