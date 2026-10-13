defmodule Shop.Notifier do
  @moduledoc """
  Sends order updates to customers. Retries with backoff; gives up after five tries.
  """
  use GenServer
  require Logger

  @max_attempts 5

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def notify(order_id, event) when event in [:paid, :shipped, :cancelled] do
    GenServer.cast(__MODULE__, {:notify, order_id, event, 1})
  end

  @impl true
  def init(opts), do: {:ok, %{mailer: Keyword.fetch!(opts, :mailer), sent: 0}}

  @impl true
  def handle_cast({:notify, order_id, event, attempt}, state) do
    case state.mailer.deliver(order_id, event) do
      :ok ->
        {:noreply, %{state | sent: state.sent + 1}}

      {:error, reason} when attempt < @max_attempts ->
        Logger.warning("order #{order_id}: #{inspect(reason)}, retry #{attempt}")
        Process.send_after(self(), {:retry, order_id, event, attempt + 1}, 200 * 2 ** attempt)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("order #{order_id}: giving up after #{attempt} tries (#{inspect(reason)})")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:retry, order_id, event, attempt}, state) do
    handle_cast({:notify, order_id, event, attempt}, state)
  end
end
