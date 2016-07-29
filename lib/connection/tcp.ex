defmodule LogstashJson.TCP.Connection do
  use Connection
  require Logger

  def start_link(host, port, opts, timeout \\ 1000) do
    Connection.start_link(__MODULE__, {host, port, opts, timeout})
  end

  def send(conn, data), do: Connection.call(conn, {:send, data})

  def recv(conn, bytes, timeout \\ 1000) do
    Connection.call(conn, {:recv, bytes, timeout})
  end

  def close(conn), do: Connection.call(conn, :close)

  def init({host, port, opts, timeout}) do
    state = %{host: host, port: port, opts: opts, timeout: timeout, sock: nil}
    {:connect, :init, state}
  end

  def connect(_, %{sock: nil, host: host, port: port, opts: opts, timeout: timeout} = state) do
    case :gen_tcp.connect(host, port, [active: false] ++ opts, timeout) do
      {:ok, sock} ->
        {:ok, %{state | sock: sock}}
      {:error, _} ->
        {:backoff, 1000, state}
    end
  end

  def disconnect(info, %{sock: sock, host: host, port: port} = state) do
    :ok = :gen_tcp.close(sock)
    case info do
      {:close, from} ->
        Connection.reply(from, :ok)
      {:error, :closed} ->
        Logger.error("#{host}:#{Integer.to_string(port)} connection closed")
      {:error, reason} ->
        reason = :inet.format_error(reason)
        Logger.error("#{host}:#{Integer.to_string(port)} connection error: #{reason}")
    end
    {:connect, :reconnect, %{state | sock: nil}}
  end

  def handle_call(_, _, %{sock: nil} = state) do
    {:reply, {:error, :closed}, state}
  end
  def handle_call({:send, data}, _, %{sock: sock} = state) do
    case :gen_tcp.send(sock, data) do
      :ok ->
        {:reply, :ok, state}
      {:error, _} = error ->
        {:disconnect, error, error, state}
    end
  end
  def handle_call({:recv, bytes, timeout}, _, %{sock: sock} = state) do
    case :gen_tcp.recv(sock, bytes, timeout) do
      {:ok, _} = ok ->
        {:reply, ok, state}
      {:error, :timeout} = timeout ->
        {:reply, timeout, state}
      {:error, _} = error ->
        {:disconnect, error, error, state}
    end
  end
  def handle_call(:close, from, state) do
    {:disconnect, {:close, from}, state}
  end
end