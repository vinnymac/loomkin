defmodule Loomkin.Tools.TeamSpawn do
  @moduledoc "Spawn a team with agents."

  @valid_roles ~w(lead researcher coder reviewer tester concierge orienter weaver)

  use Jido.Action,
    name: "team_spawn",
    description:
      "Create a new agent team and spawn agents with specified roles. " <>
        "Valid roles: researcher (read-only exploration), coder (implementation), " <>
        "reviewer (code review), tester (run tests), lead (coordination), " <>
        "weaver (knowledge routing and context coordination). " <>
        "You MUST provide a roles list with name and role for each agent. " <>
        "Returns a team status summary with team_id and agent list.",
    schema: [
      team_name: [type: :string, required: true, doc: "Human-readable team name"],
      purpose: [
        type: :string,
        required: true,
        doc:
          "Brief description of what this team will do and why it's being created. Shown to the user in the spawn approval prompt."
      ],
      roles: [
        type: {:list, :map},
        required: true,
        doc:
          "List of %{name, role} maps. role must be one of: researcher, coder, reviewer, tester, lead"
      ],
      project_path: [type: :string, doc: "Path to the project for agents to work on"],
      spawn_type: [
        type: :atom,
        required: false,
        doc:
          "Optional spawn type. Use :research for auto-approved research sub-teams (skips human gate, budget check still runs)."
      ]
    ]

  import Loomkin.Tool, only: [param!: 2, param: 2]

  alias Loomkin.Teams.Agent
  alias Loomkin.Teams.Manager

  @impl true
  def run(params, context) do
    team_name = param!(params, :team_name)
    purpose = param!(params, :purpose)
    project_path = param(params, :project_path) || param(context, :project_path)
    parent_team_id = param(context, :parent_team_id)
    session_id = param(context, :session_id)
    model = param(context, :model)
    agent_name = param(context, :agent_name) || "architect"

    roles = param!(params, :roles)

    spawn_from_roles(
      team_name,
      purpose,
      roles,
      project_path,
      parent_team_id,
      session_id,
      model,
      agent_name
    )
  end

  defp spawn_from_roles(
         team_name,
         purpose,
         roles,
         project_path,
         parent_team_id,
         session_id,
         model,
         agent_name
       ) do
    require Logger

    Logger.info(
      "[Kin:team_spawn] team=#{team_name} roles=#{inspect(roles)} parent=#{inspect(parent_team_id)}"
    )

    {:ok, team_id} =
      if parent_team_id do
        Manager.create_sub_team(parent_team_id, agent_name,
          name: team_name,
          project_path: project_path
        )
      else
        Manager.create_team(name: team_name, project_path: project_path)
      end

    spawn_opts =
      [project_path: project_path]
      |> then(fn opts -> if session_id, do: [{:session_id, session_id} | opts], else: opts end)
      |> then(fn opts -> if model, do: [{:model, model} | opts], else: opts end)

    spawn_results =
      Enum.map(roles, fn role_map ->
        name = Map.get(role_map, :name) || Map.get(role_map, "name")
        role = Map.get(role_map, :role) || Map.get(role_map, "role")
        role_atom = resolve_role(role)

        if is_nil(role_atom) do
          {:error, name, role, "unknown role. Valid: #{Enum.join(@valid_roles, ", ")}"}
        else
          case Manager.spawn_agent(team_id, name, role_atom, spawn_opts) do
            {:ok, _pid} -> {:ok, name, role_atom}
            {:error, reason} -> {:error, name, role_atom, inspect(reason)}
          end
        end
      end)

    # Build and send team manifest to each successfully spawned agent
    successful_agents =
      Enum.flat_map(spawn_results, fn
        {:ok, name, role} -> [%{name: name, role: role}]
        _ -> []
      end)

    Enum.each(successful_agents, fn %{name: spawned_name} ->
      other_agents = Enum.reject(successful_agents, &(&1.name == spawned_name))

      personal_manifest =
        format_personal_manifest(spawned_name, team_name, purpose, other_agents)

      case Manager.find_agent(team_id, spawned_name) do
        {:ok, pid} -> Agent.peer_message(pid, "system", personal_manifest)
        _ -> :ok
      end
    end)

    lines =
      Enum.map(spawn_results, fn
        {:ok, name, role} -> "  - #{name} (#{role}): spawned"
        {:error, name, role, reason} -> "  - #{name} (#{role}): failed - #{reason}"
      end)

    summary = """
    Team "#{team_name}" created (id: #{team_id})
    Agents:
    #{Enum.join(lines, "\n")}
    """

    {:ok, %{result: String.trim(summary), team_id: team_id}}
  end

  # Resolve a role string to one of the valid role atoms.
  # Handles exact matches, and falls back to keyword matching for
  # descriptive strings like "Analyze code quality and patterns".
  defp resolve_role(role) when is_atom(role), do: role

  defp resolve_role(role) when is_binary(role) do
    downcased = String.downcase(role)

    # Exact match first
    if downcased in @valid_roles do
      String.to_existing_atom(downcased)
    else
      # Keyword-based fuzzy match for descriptive role strings
      cond do
        String.contains?(downcased, "review") ->
          :reviewer

        String.contains?(downcased, "test") ->
          :tester

        String.contains?(downcased, "code") or String.contains?(downcased, "implement") ->
          :coder

        String.contains?(downcased, "research") or String.contains?(downcased, "analy") or
          String.contains?(downcased, "audit") or String.contains?(downcased, "explor") or
          String.contains?(downcased, "investigat") or String.contains?(downcased, "document") ->
          :researcher

        String.contains?(downcased, "weav") or String.contains?(downcased, "coordinat") or
            String.contains?(downcased, "glue") ->
          :weaver

        String.contains?(downcased, "lead") ->
          :lead

        String.contains?(downcased, "concierge") or String.contains?(downcased, "host") ->
          :concierge

        String.contains?(downcased, "orient") or String.contains?(downcased, "scanner") ->
          :orienter

        # If the LLM sends a security/quality/architecture analysis role, map to researcher
        String.contains?(downcased, "security") or String.contains?(downcased, "quality") or
          String.contains?(downcased, "architect") or String.contains?(downcased, "coverage") ->
          :researcher

        true ->
          nil
      end
    end
  end

  defp resolve_role(_), do: nil

  defp format_personal_manifest(my_name, team_name, purpose, teammates) do
    teammate_lines =
      Enum.map(teammates, fn %{name: name, role: role} ->
        comm_hint = communication_hint(role)
        "- **#{name}** (#{role})#{comm_hint}"
      end)
      |> Enum.join("\n")

    """
    [Team Briefing] You are #{my_name} in team "#{team_name}".
    Purpose: #{purpose}

    Your teammates:
    #{teammate_lines}

    Use peer_message to communicate. Check search_keepers for prior context before starting work.
    """
  end

  defp communication_hint(:weaver), do: " — your knowledge coordinator, keep them updated"
  defp communication_hint(:lead), do: " — your team lead"
  defp communication_hint(_), do: ""
end
