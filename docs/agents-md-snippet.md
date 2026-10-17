把下面的规则加入 `~/.codex/AGENTS.md`，让 Codex 主 agent 在各项目中使用原生调度；只对单个项目启用时，加入该项目的 `AGENTS.md`。技能先通过 `bash ./install-codex.sh` 安装。

```markdown
## Codex 主 agent 调度

读代码理解现状、排查 bug、写实现、做 review 等需要委派的任务，主 agent 先加载 `~/.codex/skills/codex-director/SKILL.md`，按技能流程写任务书、派发完整任务、核对结果、做取舍并完成交付。简单任务和给人看的文档直接处理。收到父 agent 任务书的子 agent 作为执行器完成任务，只有父 agent 明确分配进一步委派时才继续派生。

通过原生 `collaboration.spawn_agent` 派发任务，用 `fork_turns: "none"` 和自包含任务书说明目录、范围、上下文与验收要求。互不依赖的任务并行执行，并发数遵守当前宿主限制；模型和推理设置默认继承当前配置。并行写入分配独立工作树或目录。

向运行中的 agent 补充事实或决定用 `send_message`；同一问题的后续工作用 `followup_task`，它也负责启动空闲 agent 的下一轮。必须立刻停止当前执行再改方向时，先 `interrupt_agent`，检查已有改动后再安排后续任务。用 `wait_agent` 等待消息、用 `list_agents` 检查状态；15 分钟无进展时检查存活和阻塞情况。同一问题尽量保留同一个 agent，独立复核使用新 agent。

子 agent 的结论核对原始证据后再采用；主 agent 负责转发跨任务信息、集成改动、执行必要的定向验证并汇报。只读、修改、提交、推送和部署的权限沿用用户授权，缺少信息或授权时先报告，不自行推断。
```
