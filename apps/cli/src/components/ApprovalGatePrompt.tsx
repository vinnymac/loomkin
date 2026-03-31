import React, { useState } from "react";
import { Box, Text, useInput } from "ink";
import TextInput from "ink-text-input";
import type { ApprovalRequest, SpawnGateRequest } from "../lib/types.js";

type Props =
  | {
      type: "approval";
      gate: ApprovalRequest;
      onRespond: (gateId: string, outcome: "approved" | "denied", context?: string, reason?: string) => void;
    }
  | {
      type: "spawn_gate";
      gate: SpawnGateRequest;
      onRespond: (gateId: string, outcome: "approved" | "denied", reason?: string) => void;
    };

export function ApprovalGatePrompt(props: Props) {
  const [mode, setMode] = useState<"choose" | "context" | "reason">("choose");
  const [text, setText] = useState("");
  const { gate } = props;

  useInput(
    (input) => {
      if (mode !== "choose") return;

      if (input === "y") {
        if (props.type === "approval") {
          props.onRespond(gate.gate_id, "approved");
        } else {
          props.onRespond(gate.gate_id, "approved");
        }
      } else if (input === "n") {
        setMode("reason");
      } else if (input === "c" && props.type === "approval") {
        setMode("context");
      }
    },
    { isActive: mode === "choose" },
  );

  const handleTextSubmit = (value: string) => {
    if (mode === "context" && props.type === "approval") {
      props.onRespond(gate.gate_id, "approved", value);
    } else if (mode === "reason") {
      if (props.type === "approval") {
        props.onRespond(gate.gate_id, "denied", undefined, value || "denied by user");
      } else {
        props.onRespond(gate.gate_id, "denied", value || "denied by user");
      }
    }
  };

  const elapsed = Math.round((Date.now() - gate.received_at) / 1000);
  const remaining = Math.max(0, Math.round(gate.timeout_ms / 1000) - elapsed);

  return (
    <Box
      borderStyle="round"
      borderColor="magenta"
      paddingX={1}
      flexDirection="column"
    >
      {props.type === "approval" ? (
        <>
          <Text bold color="magenta">
            {gate.agent_name} requests approval
          </Text>
          <Text>{(gate as ApprovalRequest).question}</Text>
        </>
      ) : (
        <>
          <Text bold color="magenta">
            {gate.agent_name} wants to spawn agents
          </Text>
          {(gate as SpawnGateRequest).purpose && (
            <Text dimColor>Purpose: {(gate as SpawnGateRequest).purpose}</Text>
          )}
          <Box marginTop={1} flexDirection="column">
            {(gate as SpawnGateRequest).roles.map((r, i) => (
              <Text key={`role-${i}`}>
                {"  "}• {r.name ? `${r.name} (${r.role})` : r.role}
              </Text>
            ))}
          </Box>
          <Text>
            Estimated cost:{" "}
            <Text
              color={
                (gate as SpawnGateRequest).estimated_cost >= 1
                  ? "red"
                  : (gate as SpawnGateRequest).estimated_cost >= 0.1
                    ? "yellow"
                    : "green"
              }
            >
              ${(gate as SpawnGateRequest).estimated_cost.toFixed(4)}
            </Text>
          </Text>
          {(gate as SpawnGateRequest).limit_warning && (
            <Text color="yellow">⚠ {(gate as SpawnGateRequest).limit_warning}</Text>
          )}
        </>
      )}

      <Text dimColor>Timeout: {remaining}s remaining</Text>

      {mode === "choose" && (
        <Box marginTop={1}>
          <Text>
            <Text bold color="green">[y]</Text> approve{"  "}
            <Text bold color="red">[n]</Text> deny
            {props.type === "approval" && (
              <>
                {"  "}
                <Text bold color="cyan">[c]</Text> approve with context
              </>
            )}
          </Text>
        </Box>
      )}

      {(mode === "context" || mode === "reason") && (
        <Box marginTop={1} flexDirection="column">
          <Text dimColor>
            {mode === "context" ? "Add context:" : "Reason for denial:"}
          </Text>
          <Box>
            <Text dimColor>{"› "}</Text>
            <TextInput
              value={text}
              onChange={setText}
              onSubmit={handleTextSubmit}
              placeholder={mode === "context" ? "Optional context..." : "Reason..."}
            />
          </Box>
        </Box>
      )}
    </Box>
  );
}
