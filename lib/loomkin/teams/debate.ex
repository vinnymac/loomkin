defmodule Loomkin.Teams.Debate do
  @moduledoc """
  Orchestrates structured multi-agent debate within a team.

  Runs a propose -> critique -> revise -> vote cycle across participants,
  logging proposals and critiques to the decision graph. Not a GenServer —
  coordinates via existing agent infrastructure and `Comms`.
  """

  alias Loomkin.Decisions.Graph
  alias Loomkin.Teams.Comms

  @default_max_rounds 3
  @default_round_timeout_ms 30_000

  @type vote_map :: %{optional(String.t()) => String.t()}
  @type round_data :: %{
          round: pos_integer(),
          proposals: [map()],
          critiques: [map()],
          revisions: [map()]
        }
  @type debate_result :: %{
          winner: map() | nil,
          votes: vote_map(),
          rounds: [round_data()],
          consensus?: boolean()
        }

  @doc """
  Initiate a structured debate among participants on a given topic.

  ## Options

    * `:max_rounds` - maximum number of debate rounds (default #{@default_max_rounds})
    * `:round_timeout_ms` - timeout per round phase in ms (default #{@default_round_timeout_ms})
    * `:session_id` - optional session ID for decision graph nodes

  Returns `{:ok, debate_result}` or `{:error, reason}`.
  """
  @spec initiate_debate(String.t(), String.t(), [String.t()], keyword()) ::
          {:ok, debate_result()} | {:error, atom()}
  def initiate_debate(team_id, topic, participants, opts \\ [])

  def initiate_debate(_team_id, _topic, participants, _opts)
      when length(participants) < 2 do
    {:error, :insufficient_participants}
  end

  def initiate_debate(team_id, topic, participants, opts) do
    max_rounds = Keyword.get(opts, :max_rounds, @default_max_rounds)
    round_timeout = Keyword.get(opts, :round_timeout_ms, @default_round_timeout_ms)
    session_id = Keyword.get(opts, :session_id)

    debate_id = Ecto.UUID.generate()

    # Subscribe the current process to a dedicated debate topic
    debate_topic = "team:#{team_id}:debate:#{debate_id}"
    Phoenix.PubSub.subscribe(Loomkin.PubSub, debate_topic)

    # Notify participants that a debate has started
    Enum.each(participants, fn participant ->
      Comms.send_to(team_id, participant, {:debate_start, debate_id, topic, participants})
    end)

    rounds =
      Enum.map(1..max_rounds, fn round_num ->
        {:ok, round_data} =
          run_round(team_id, debate_id, topic, participants, round_num, round_timeout, session_id)

        round_data
      end)

    result = tally_and_build_result(team_id, debate_id, topic, participants, rounds, round_timeout, session_id)
    {:ok, result}
  end

  # -- Round execution --

  defp run_round(team_id, debate_id, topic, participants, round_num, timeout, session_id) do
    # Phase 1: Propose
    Enum.each(participants, fn participant ->
      Comms.send_to(team_id, participant, {:debate_propose, debate_id, round_num, topic})
    end)

    proposals = collect_responses(debate_id, :proposal, participants, timeout)

    # Log proposals to decision graph
    proposal_nodes =
      Enum.map(proposals, fn proposal ->
        {:ok, node} =
          Graph.add_node(%{
            node_type: :option,
            title: "Debate proposal: #{truncate(proposal.content, 80)}",
            description: proposal.content,
            confidence: proposal[:confidence] || 50,
            agent_name: proposal.from,
            session_id: session_id,
            metadata: %{debate_id: debate_id, round: round_num, phase: "proposal"}
          })

        Comms.broadcast_decision(team_id, node.id, proposal.from)
        Map.put(proposal, :node_id, node.id)
      end)

    # Phase 2: Critique — each participant critiques others' proposals
    Enum.each(participants, fn participant ->
      others = Enum.reject(proposal_nodes, &(&1.from == participant))

      Comms.send_to(team_id, participant, {
        :debate_critique,
        debate_id,
        round_num,
        others
      })
    end)

    critiques = collect_responses(debate_id, :critique, participants, timeout)

    # Log critiques to decision graph
    Enum.each(critiques, fn critique ->
      {:ok, node} =
        Graph.add_node(%{
          node_type: :observation,
          title: "Critique by #{critique.from}",
          description: critique.content,
          confidence: critique[:confidence] || 50,
          agent_name: critique.from,
          session_id: session_id,
          metadata: %{debate_id: debate_id, round: round_num, phase: "critique"}
        })

      # Link critique to the proposal it targets
      if critique[:target_node_id] do
        Graph.add_edge(node.id, critique.target_node_id, :supports,
          rationale: "critique of proposal"
        )
      end

      Comms.broadcast_decision(team_id, node.id, critique.from)
    end)

    # Phase 3: Revise — participants may revise their proposals based on critiques
    Enum.each(participants, fn participant ->
      my_critiques = Enum.filter(critiques, &(&1[:target] == participant))

      Comms.send_to(team_id, participant, {
        :debate_revise,
        debate_id,
        round_num,
        my_critiques
      })
    end)

    revisions = collect_responses(debate_id, :revision, participants, timeout)

    {:ok,
     %{
       round: round_num,
       proposals: proposal_nodes,
       critiques: critiques,
       revisions: revisions
     }}
  end

  # -- Voting & result --

  defp tally_and_build_result(team_id, debate_id, topic, participants, rounds, timeout, session_id) do
    # Request votes from all participants
    final_proposals = build_final_proposals(rounds)

    Enum.each(participants, fn participant ->
      Comms.send_to(team_id, participant, {:debate_vote, debate_id, final_proposals})
    end)

    votes = collect_responses(debate_id, :vote, participants, timeout)
    vote_map = Map.new(votes, fn v -> {v.from, v.choice} end)

    # Get agent info for weighted voting
    agents = Loomkin.Teams.Context.list_agents(team_id)

    # Use weighted tallying
    weighted = tally_weighted_votes(votes, agents, topic, "general")

    # Find the winning proposal by weighted winner
    winner_id = weighted.winner

    winner =
      Enum.find(final_proposals, fn p ->
        p.from == winner_id || p[:node_id] == winner_id
      end)

    consensus? = weighted.consensus?

    # Log the winning decision with weight info
    if winner do
      {:ok, decision_node} =
        Graph.add_node(%{
          node_type: :decision,
          title: "Debate winner: #{truncate(winner.content, 80)}",
          description: winner.content,
          confidence: if(consensus?, do: 90, else: round(weighted.winning_weight_pct)),
          agent_name: winner.from,
          session_id: session_id,
          metadata: %{
            debate_id: debate_id,
            votes: vote_map,
            consensus: consensus?,
            weighted_tallies: weighted.weighted_tallies,
            vote_weights: weighted.vote_weights
          }
        })

      if winner[:node_id] do
        Graph.add_edge(winner.node_id, decision_node.id, :leads_to,
          rationale: "selected by weighted vote"
        )
      end
    end

    %{
      winner: winner,
      votes: vote_map,
      rounds: rounds,
      consensus?: consensus?,
      weighted_tallies: weighted.weighted_tallies,
      vote_weights: weighted.vote_weights
    }
  end

  # -- Helpers --

  defp collect_responses(debate_id, phase, participants, timeout) do
    expected = MapSet.new(participants)

    do_collect(debate_id, phase, expected, MapSet.new(), [], timeout)
  end

  defp do_collect(_debate_id, _phase, expected, received, acc, _timeout)
       when expected == received do
    acc
  end

  defp do_collect(debate_id, phase, expected, received, acc, timeout) do
    receive do
      {:debate_response, ^debate_id, ^phase, response} ->
        from = response.from

        if MapSet.member?(expected, from) and not MapSet.member?(received, from) do
          do_collect(
            debate_id,
            phase,
            expected,
            MapSet.put(received, from),
            acc ++ [response],
            timeout
          )
        else
          do_collect(debate_id, phase, expected, received, acc, timeout)
        end
    after
      timeout ->
        # Return whatever we've collected so far
        acc
    end
  end

  defp build_final_proposals(rounds) do
    case List.last(rounds) do
      nil ->
        []

      last_round ->
        # Use revisions if available, otherwise original proposals
        if last_round.revisions != [] do
          last_round.revisions
        else
          last_round.proposals
        end
    end
  end

  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "..."

  # -- Weighted Voting --

  @doc """
  Calculate the expertise weight for a given agent role and decision topic/scope.

  Returns a float between 0.5 and 2.0 representing how relevant the agent's
  role is to the decision scope. Higher weight = more expertise.

  ## Examples

      iex> Debate.expertise_weight(:coder, "code")
      2.0

      iex> Debate.expertise_weight(:researcher, "code")
      1.0
  """
  @spec expertise_weight(atom(), String.t()) :: float()
  def expertise_weight(role, scope) when is_atom(role) and is_binary(scope) do
    scope = String.downcase(scope)

    role_strengths = %{
      lead: ~w(architecture planning coordination general),
      coder: ~w(code implementation refactoring debugging),
      researcher: ~w(research analysis investigation codebase),
      reviewer: ~w(code review quality security),
      tester: ~w(testing validation quality)
    }

    strengths = Map.get(role_strengths, role, [])

    cond do
      scope in strengths -> 2.0
      scope == "general" -> 1.0
      partial_match?(strengths, scope) -> 1.5
      true -> 0.5
    end
  end

  def expertise_weight(_role, _scope), do: 1.0

  defp partial_match?(strengths, scope) do
    Enum.any?(strengths, fn s ->
      String.contains?(scope, s) or String.contains?(s, scope)
    end)
  end

  @doc """
  Compute the overall vote weight for an agent.

  Combines three factors:
  - Role expertise weight (0.5-2.0) based on role vs decision scope
  - Capability score (0.0-1.0) from agent info, defaults to 0.5
  - Stated confidence (0.0-1.0) from the vote itself, defaults to 0.5

  Final weight = expertise * (0.5 + 0.25 * capability + 0.25 * confidence)
  """
  @spec compute_vote_weight(map(), atom(), String.t(), float()) :: float()
  def compute_vote_weight(agent_info, role, scope, stated_confidence \\ 0.5) do
    expertise = expertise_weight(role, scope)
    capability = Map.get(agent_info, :capability_score, 0.5)
    confidence = clamp(stated_confidence, 0.0, 1.0)

    expertise * (0.5 + 0.25 * capability + 0.25 * confidence)
  end

  @doc """
  Tally votes with weights. Returns a result map with raw tallies, weighted
  tallies, per-agent weights, winner, and consensus flag.

  ## Parameters
  - `votes` — list of `%{from: name, choice: option, confidence: 0.0..1.0}`
  - `agents` — list of agent info maps `%{name: _, role: _, ...}`
  - `topic` — the decision topic string
  - `scope` — the decision scope for expertise weighting
  """
  @spec tally_weighted_votes([map()], [map()], String.t(), String.t()) :: map()
  def tally_weighted_votes(votes, agents, _topic, scope) do
    agent_map = Map.new(agents, fn a -> {to_string(a.name), a} end)

    # Compute per-voter weight
    vote_weights =
      Map.new(votes, fn vote ->
        from = to_string(vote.from)
        agent = Map.get(agent_map, from, %{role: :coder})
        role = agent[:role] || :coder
        confidence = vote[:confidence] || 0.5

        {from, compute_vote_weight(agent, role, scope, confidence)}
      end)

    # Raw tallies (simple count)
    raw_tallies =
      Enum.reduce(votes, %{}, fn vote, acc ->
        choice = to_string(vote.choice)
        Map.update(acc, choice, 1, &(&1 + 1))
      end)

    # Weighted tallies
    weighted_tallies =
      Enum.reduce(votes, %{}, fn vote, acc ->
        choice = to_string(vote.choice)
        from = to_string(vote.from)
        weight = Map.get(vote_weights, from, 1.0)
        Map.update(acc, choice, weight, &(&1 + weight))
      end)

    # Determine winner by weighted tally
    {winner, winning_weight} =
      if weighted_tallies == %{} do
        {nil, 0.0}
      else
        Enum.max_by(weighted_tallies, fn {_k, v} -> v end)
      end

    total_weight = Enum.reduce(weighted_tallies, 0.0, fn {_k, v}, acc -> acc + v end)

    winning_weight_pct =
      if total_weight > 0, do: winning_weight / total_weight * 100, else: 0.0

    unique_choices = Map.keys(weighted_tallies)
    consensus? = length(unique_choices) <= 1 and length(votes) > 0

    %{
      winner: winner,
      raw_tallies: raw_tallies,
      weighted_tallies: weighted_tallies,
      vote_weights: vote_weights,
      consensus?: consensus?,
      winning_weight_pct: winning_weight_pct
    }
  end

  defp clamp(val, min, max), do: val |> Kernel.max(min) |> Kernel.min(max)

  @doc """
  Submit a debate response from a participant.

  Called by agents (or tools) to submit their response to a debate phase.
  Broadcasts on the debate PubSub topic so the orchestrator can collect it.
  """
  @spec submit_response(String.t(), String.t(), atom(), map()) :: :ok
  def submit_response(team_id, debate_id, phase, response) do
    Phoenix.PubSub.broadcast(
      Loomkin.PubSub,
      "team:#{team_id}:debate:#{debate_id}",
      {:debate_response, debate_id, phase, response}
    )
  end
end
