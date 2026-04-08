defmodule LoomkinWeb.SessionChannelTest do
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest

  import Loomkin.AccountsFixtures

  alias Loomkin.Accounts.Scope
  alias Loomkin.Session.Persistence
  alias LoomkinWeb.SessionChannel

  @endpoint LoomkinWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Loomkin.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Loomkin.Repo, {:shared, self()})

    user = user_fixture()
    scope = Scope.for_user(user)

    {:ok, user: user, scope: scope}
  end

  defp runtime_team_id(session_id, fallback_team_id, attempts \\ 20)

  defp runtime_team_id(_session_id, fallback_team_id, 0), do: fallback_team_id

  defp runtime_team_id(session_id, fallback_team_id, attempts) do
    team_id =
      session_id
      |> Persistence.get_session()
      |> case do
        %{team_id: team_id} when is_binary(team_id) and team_id != "" -> team_id
        _ -> fallback_team_id
      end

    if team_id != fallback_team_id do
      team_id
    else
      Process.sleep(10)
      runtime_team_id(session_id, fallback_team_id, attempts - 1)
    end
  end

  test "forwards peer_message content from signal data message field", %{user: user, scope: scope} do
    {:ok, session} =
      Persistence.create_session(%{
        model: "anthropic:claude-sonnet-4-5",
        project_path: "/tmp",
        team_id: "team-123",
        user_id: user.id
      })

    socket = socket(LoomkinWeb.UserSocket, "user_socket:#{user.id}", %{current_scope: scope})

    {:ok, _, socket} =
      subscribe_and_join(socket, SessionChannel, "session:#{session.id}")

    receive do
      {:email, _email} -> :ok
    after
      0 -> :ok
    end

    signal =
      Loomkin.Signals.Collaboration.PeerMessage.new!(%{
        from: "system",
        team_id: "team-123"
      })

    signal = %{
      signal
      | data:
          Map.merge(signal.data, %{
            target: "concierge",
            message: {:peer_message, "system", "spawned researcher"}
          })
    }

    send(socket.channel_pid, signal)

    assert_push "peer_message", %{
      from: "system",
      to: "concierge",
      content: "spawned researcher",
      team_id: "team-123"
    }
  end

  test "formats max-iteration agent errors for cli consumers", %{user: user, scope: scope} do
    initial_team_id = "team-123"

    {:ok, session} =
      Persistence.create_session(%{
        model: "anthropic:claude-sonnet-4-5",
        project_path: "/tmp",
        team_id: initial_team_id,
        user_id: user.id
      })

    socket = socket(LoomkinWeb.UserSocket, "user_socket:#{user.id}", %{current_scope: scope})

    {:ok, _, socket} =
      subscribe_and_join(socket, SessionChannel, "session:#{session.id}")

    receive do
      {:email, _email} -> :ok
    after
      0 -> :ok
    end

    team_id = runtime_team_id(session.id, initial_team_id)

    signal =
      Loomkin.Signals.Agent.Error.new!(%{
        agent_name: "concierge",
        team_id: team_id
      })

    signal = %{
      signal
      | data:
          Map.merge(signal.data, %{
            payload: %{iterations: 30, max: 30}
          })
    }

    send(socket.channel_pid, {:signal, signal})

    assert_push(
      "agent_error",
      %{
        agent_name: "concierge",
        error: "Exceeded max iterations (30)"
      },
      500
    )
  end

  test "forwards findings publication events for cli agent indicators", %{
    user: user,
    scope: scope
  } do
    initial_team_id = "team-123"

    {:ok, session} =
      Persistence.create_session(%{
        model: "anthropic:claude-sonnet-4-5",
        project_path: "/tmp",
        team_id: initial_team_id,
        user_id: user.id
      })

    socket = socket(LoomkinWeb.UserSocket, "user_socket:#{user.id}", %{current_scope: scope})

    {:ok, _, socket} =
      subscribe_and_join(socket, SessionChannel, "session:#{session.id}")

    receive do
      {:email, _email} -> :ok
    after
      0 -> :ok
    end

    team_id = runtime_team_id(session.id, initial_team_id)

    signal =
      Loomkin.Signals.Context.Offloaded.new!(%{
        agent_name: "researcher-1",
        team_id: team_id
      })

    signal = %{
      signal
      | data:
          Map.merge(signal.data, %{
            payload: %{
              topic: "research: cli layout audit",
              source: "peer_complete_task",
              task_id: "task-123"
            }
          })
    }

    send(socket.channel_pid, {:signal, signal})

    assert_push(
      "agent_findings_published",
      %{
        agent_name: "researcher-1",
        team_id: ^team_id,
        topic: "research: cli layout audit",
        source: "peer_complete_task",
        task_id: "task-123"
      },
      500
    )
  end
end
