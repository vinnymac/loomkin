defmodule Loomkin.Teams.AgentResearchProtocolTest do
  use ExUnit.Case, async: false

  @moduletag :skip

  # ---------------------------------------------------------------------------
  # Helper: start a bare agent process for handle_call / :sys.get_state testing.
  # Mirrors the pattern in agent_spawn_gate_test.exs.
  # ---------------------------------------------------------------------------

  defp unique_team_id, do: "test-team-#{System.unique_integer([:positive])}"
  defp unique_name, do: "agent-#{System.unique_integer([:positive])}"

  defp start_agent(opts \\ []) do
    # stub — Wave 1 will implement this using Agent.start_link with team_id,
    # name, role, and budget assigns, mirroring agent_spawn_gate_test.exs
    _team_id = Keyword.get(opts, :team_id, unique_team_id())
    _name = Keyword.get(opts, :name, unique_name())
    flunk("start_agent not implemented")
  end

  # ---------------------------------------------------------------------------
  # 1. spawn_type: :research auto-approve path
  # ---------------------------------------------------------------------------

  describe "spawn_type: :research auto-approve path" do
    @tag :skip
    test "run_spawn_gate_intercept takes auto-approve path when tool_args has spawn_type: research (string key)" do
      flunk("not implemented")
    end

    @tag :skip
    test "run_spawn_gate_intercept takes auto-approve path when tool_args has spawn_type: :research (atom key)" do
      flunk("not implemented")
    end

    @tag :skip
    test "auto-approve path bypasses the human gate ui (no :approval_pending status)" do
      flunk("not implemented")
    end
  end

  # ---------------------------------------------------------------------------
  # 2. budget check still runs for research spawns
  # ---------------------------------------------------------------------------

  describe "budget check still runs for research spawns" do
    @tag :skip
    test "research spawn exceeding remaining budget returns {:error, :budget_exceeded, _}" do
      _pid = start_agent()
      flunk("not implemented")
    end
  end

  # ---------------------------------------------------------------------------
  # 3. :awaiting_synthesis status transition
  # ---------------------------------------------------------------------------

  describe ":awaiting_synthesis status transition" do
    @tag :skip
    test "agent transitions to :awaiting_synthesis after a research spawn is approved" do
      _pid = start_agent()
      flunk("not implemented")
    end

    @tag :skip
    test "handle_cast(:request_pause) queues pause rather than immediately pausing when status is :awaiting_synthesis" do
      _pid = start_agent()
      flunk("not implemented")
    end
  end

  # ---------------------------------------------------------------------------
  # 4. peer_message routing to tool task during :awaiting_synthesis
  # ---------------------------------------------------------------------------

  describe "peer_message routing to tool task during :awaiting_synthesis" do
    @tag :skip
    test "incoming peer_message cast is forwarded to registered tool task pid when agent is :awaiting_synthesis" do
      _pid = start_agent()
      flunk("not implemented")
    end

    @tag :skip
    test "peer_message is not appended to messages list when agent is :awaiting_synthesis" do
      _pid = start_agent()
      flunk("not implemented")
    end
  end
end
