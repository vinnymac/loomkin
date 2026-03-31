import pc from "picocolors";
import { register, type CommandContext } from "./registry.js";
import { getSessionChannel } from "./channelUtil.js";

register({
  name: "inject",
  description: "Inject non-disruptive guidance to an active agent",
  args: "<agent-name> <text>",
  handler: async (args: string, ctx: CommandContext) => {
    const channel = getSessionChannel();
    if (!channel) {
      ctx.addSystemMessage(pc.red("No active session."));
      return;
    }

    const parts = args.trim().split(/\s+/);
    const agentName = parts[0];
    const text = parts.slice(1).join(" ");

    if (!agentName || !text) {
      ctx.addSystemMessage(pc.red("Usage: /inject <agent-name> <guidance text>"));
      return;
    }

    channel
      .push("inject_guidance", { agent_name: agentName, text })
      .receive("ok", () => {
        ctx.addSystemMessage(
          `${pc.cyan("💉")} Guidance injected for ${pc.bold(agentName)}`,
        );
      })
      .receive("error", (raw: Record<string, unknown>) => {
        const reason = typeof raw?.reason === "string" ? raw.reason : "unknown error";
        ctx.addSystemMessage(pc.red(`Failed: ${reason}`));
      });
  },
});
