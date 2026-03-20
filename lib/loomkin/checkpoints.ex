defmodule Loomkin.Checkpoints do
  @moduledoc "Context module for agent checkpoint persistence."

  import Ecto.Query

  alias Loomkin.Repo
  alias Loomkin.Schemas.AgentCheckpoint

  @doc "Create a new agent checkpoint."
  def create_checkpoint(attrs) do
    %AgentCheckpoint{}
    |> AgentCheckpoint.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get the latest checkpoint for a given team and agent."
  def latest_checkpoint(team_id, agent_name) do
    from(c in AgentCheckpoint,
      where: c.team_id == ^team_id and c.agent_name == ^agent_name,
      order_by: [desc: c.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc "List all checkpoints for a team."
  def list_checkpoints(team_id) do
    from(c in AgentCheckpoint,
      where: c.team_id == ^team_id,
      order_by: [desc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Delete old checkpoints for a team, keeping the N most recent per agent."
  def delete_old_checkpoints(team_id, opts \\ []) do
    keep = Keyword.get(opts, :keep, 3)

    agents =
      from(c in AgentCheckpoint,
        where: c.team_id == ^team_id,
        select: c.agent_name,
        distinct: true
      )
      |> Repo.all()

    Enum.each(agents, fn agent_name ->
      keep_ids =
        from(c in AgentCheckpoint,
          where: c.team_id == ^team_id and c.agent_name == ^agent_name,
          order_by: [desc: c.inserted_at],
          limit: ^keep,
          select: c.id
        )
        |> Repo.all()

      from(c in AgentCheckpoint,
        where:
          c.team_id == ^team_id and
            c.agent_name == ^agent_name and
            c.id not in ^keep_ids
      )
      |> Repo.delete_all()
    end)

    :ok
  end
end
