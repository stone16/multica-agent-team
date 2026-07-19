# Official Outreach Kit / 官方对接宣传包

This document is a ready-to-review package for introducing the public Multica Agent Team reference project to the Multica team or other official channels. It is intentionally a draft: replace bracketed fields, attach current evidence, and obtain human approval before sending.

本文档是一份可直接审阅的官方对接材料，用于向 Multica 团队或其他官方渠道介绍公开的 Multica Agent Team 参考项目。它是草稿包：发送前请替换方括号中的字段、附上最新证据，并取得人工确认。

## 1. One-line description / 一句话介绍

**English:** Multica Agent Team is a public operating model for reusable AI agent teams, separating stable professions and Squad contracts from changeable deployment identities and Issue-scoped runs.

**中文：** Multica Agent Team 是一个公开的可复用 AI Agent 团队参考模型，将稳定的专业能力与 Squad 契约，和可变化的部署身份、Issue 运行上下文清晰分开。

## 2. Short pitch / 对外短介绍

**English**

Multica Agent Team treats an agent company as a versioned operating system rather than a collection of prompts. This public repository defines seven reusable professions, five functional Squads, bounded delegation with Definition of Done, independent verification, and non-destructive synchronization into Multica. The design keeps capability and governance reviewable in Git while leaving runtime identity, model choice, capacity, and run context configurable at deployment time.

**中文**

Multica Agent Team 将 Agent 公司视为一个可版本化的操作系统，而不是一组孤立的 prompt。仓库定义了七个可复用专业、五个功能 Squad、带 Definition of Done 的有边界委派、独立验证，以及面向 Multica 的非破坏式同步。这样，能力和治理可以在 Git 中审查，而运行时身份、模型选择、容量和每次 Run 的上下文仍可在部署时配置。

## 3. Why it may be useful to Multica / 对 Multica 的价值

- **A concrete reference implementation / 可参考的具体实现：** turns concepts such as agent roles, squads, routing, and verification into inspectable files and tests.
- **A reusable adoption pattern / 可复用的采用模式：** gives teams a starting point for separating profession capability, instance identity, Squad routing, and run state.
- **A feedback surface / 反馈入口：** exposes practical questions about synchronization, review gates, memory boundaries, and safe topology changes.
- **Community education / 社区教育：** provides bilingual documentation and a visual explanation of what is stable versus what changes at deployment time.

These are proposed collaboration benefits, not claims of official endorsement. / 以上是拟议的合作价值，不代表官方背书。

## 4. Email or direct-message template / 邮件或私信模板

### English

**Subject:** Public Multica Agent Team reference project

Hello [name/team],

I maintain [Multica Agent Team](https://github.com/stone16/multica-agent-team), a public reference project for organizing reusable AI agent teams on Multica.

The repository models seven stable professional profiles and five persistent functional Squads. It also documents a bounded Issue workflow: the Orchestrator selects the smallest sufficient team, delegates with a Definition of Done, collects evidence, and routes independent verification when needed. Runtime identities, model choices, and run context remain deployment-level concerns rather than hard-coded product state.

I would appreciate your guidance on whether this project could be useful for an official showcase, community example, documentation link, or future ecosystem conversation. I am happy to provide a short demo, architecture walkthrough, or a concise case study. I will not represent the project as officially endorsed without your approval.

Repository: https://github.com/stone16/multica-agent-team
Documentation: https://github.com/stone16/multica-agent-team/blob/main/docs/operating-model.md

Best,
[name]

### 中文

**主题：** 公开 Multica Agent Team 参考项目，希望获得官方建议

您好，[姓名/团队]：

我正在维护 [Multica Agent Team](https://github.com/stone16/multica-agent-team)，这是一个用于在 Multica 上组织可复用 AI Agent 团队的公开参考项目。

仓库目前定义了七个稳定的专业角色和五个持久化功能 Squad，并记录了一套有边界的 Issue 流程：Orchestrator 选择足够完成任务的最小团队，以 Definition of Done 进行委派，收集证据，并在需要时进入独立验证。运行时身份、模型选择和每次 Run 的上下文则保留在部署层，而不是写死为产品状态。

想请教贵方，这个项目是否适合成为官方展示、社区案例、文档链接或未来生态交流的候选项目。我可以进一步提供简短演示、架构 walkthrough 或精简案例说明。在得到确认前，我不会将项目表述为获得官方背书。

项目地址：https://github.com/stone16/multica-agent-team
技术说明：https://github.com/stone16/multica-agent-team/blob/main/docs/operating-model.md

谢谢！
[姓名]

## 5. Evidence pack / 证据包

Attach only evidence that is current and reproducible:

| Evidence | Link or artifact | Status |
|---|---|---|
| Repository overview | [`README.md`](../README.md) | Ready |
| Stable/changeable boundary diagram | [`README.md`](../README.md) | Ready |
| Full operating model | [`operating-model.md`](operating-model.md) | Ready |
| Profession profiles | [`agents/`](../agents/) | Ready |
| Squad definitions | [`squads/`](../squads/) | Ready |
| Sync and topology tests | [`tests/`](../tests/) | Verify before sending |
| Short demo or screenshots | `[attach current artifact]` | TODO |
| Maintainer contact | `[name + preferred channel]` | TODO |

Do not attach tokens, UUIDs, mention links, private repository names, or environment values. / 不要附上 token、UUID、mention 链接、私有仓库名或环境变量值。

## 6. Suggested official requests / 建议向官方提出的事项

Ask for one or more specific, low-friction next steps:

1. Review whether the project may be listed as a community example or ecosystem project.
2. Confirm the correct official contact or community channel for a technical walkthrough.
3. Request feedback on terminology, integration boundaries, and documentation accuracy.
4. If appropriate, ask whether a short maintainer interview, demo, or social post would be useful.

Avoid asking for unspecified “more promotion.” A concrete request is easier to approve, route, and measure. / 避免笼统地请求“更多宣传”；具体请求更容易被审核、转交和衡量。

## 7. Pre-send checklist / 发送前检查

- [ ] A maintainer has reviewed the message and approved the recipient/channel.
- [ ] All `[bracketed fields]` are filled in.
- [ ] Links resolve from the public `main` branch.
- [ ] Any demo or screenshot reflects the current repository.
- [ ] No official endorsement is implied without written confirmation.
- [ ] Claims are limited to behavior that can be verified in the repository.
- [ ] A follow-up owner and response date are recorded outside the repository.
