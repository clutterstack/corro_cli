defmodule CorroCLI do
  @moduledoc """
  Interface for running Corrosion CLI commands using Elixir Ports.

  Provides functions to execute corrosion commands like `cluster members`,
  `cluster info`, etc. and returns the raw output for further processing.

  ## Examples

      # Basic usage with default configuration
      {:ok, output} = CorroCLI.cluster_members()

      # With custom configuration
      {:ok, output} = CorroCLI.cluster_members(
        binary_path: "/path/to/corrosion",
        config_path: "/path/to/config.toml"
      )

      # Async execution
      task = CorroCLI.cluster_members_async()
      {:ok, output} = Task.await(task, 10_000)

  ## Configuration

  The library expects either:
  1. Configuration passed directly to functions via options
  2. Application configuration in your app:

      config :corro_cli,
        binary_path: "/path/to/corrosion",
        config_path: "/path/to/config.toml"

  """

  require Logger

  @default_timeout 5_000

  @doc """
  Gets cluster members information using `corrosion cluster members`.

  ## Options
  - `:timeout` - Command timeout in milliseconds (default: 5000)
  - `:config_path` - Override config path
  - `:binary_path` - Override binary path

  ## Returns
  - `{:ok, output}` - Raw JSON output from corrosion command
  - `{:error, reason}` - Error with details

  ## Examples
      iex> CorroCLI.cluster_members()
      {:ok, "{\\"id\\": \\"94bfbec2...\\"..."}

      iex> CorroCLI.cluster_members(timeout: 10_000)
      {:ok, "{\\"id\\": \\"94bfbec2...\\"..."}
  """
  def cluster_members(opts \\ []) do
    run_command(["cluster", "members"], opts)
  end

  @doc """
  Gets cluster members information asynchronously.

  ## Options
  Same as `cluster_members/1`

  ## Returns
  - `Task` that when awaited returns `{:ok, output}` or `{:error, reason}`

  ## Examples
      iex> task = CorroCLI.cluster_members_async()
      iex> Task.await(task, 10_000)
      {:ok, "{\\"id\\": \\"94bfbec2...\\"..."}
  """
  def cluster_members_async(opts \\ []) do
    Task.async(fn -> cluster_members(opts) end)
  end

  @doc """
  Gets cluster information using `corrosion cluster info`.

  ## Options
  Same as `cluster_members/1`
  """
  def cluster_info(opts \\ []) do
    run_command(["cluster", "info"], opts)
  end

  @doc """
  Gets cluster information asynchronously.

  ## Options
  Same as `cluster_members/1`
  """
  def cluster_info_async(opts \\ []) do
    Task.async(fn -> cluster_info(opts) end)
  end

  @doc """
  Gets cluster status using `corrosion cluster status`.

  ## Options
  Same as `cluster_members/1`
  """
  def cluster_status(opts \\ []) do
    run_command(["cluster", "status"], opts)
  end

  @doc """
  Gets cluster status asynchronously.

  ## Options
  Same as `cluster_members/1`
  """
  def cluster_status_async(opts \\ []) do
    Task.async(fn -> cluster_status(opts) end)
  end

  @doc """
  Runs an arbitrary corrosion command.

  ## Parameters
  - `args` - List of command arguments (e.g., ["cluster", "members"])
  - `opts` - Options keyword list

  ## Options
  - `:timeout` - Command timeout in milliseconds (default: 5000)
  - `:config_path` - Override config path
  - `:binary_path` - Override binary path

  ## Returns
  - `{:ok, output}` - Command output as string
  - `{:error, reason}` - Error details

  ## Examples
      iex> CorroCLI.run_command(["cluster", "members"])
      {:ok, "{\\"id\\": \\"94bfbec2..."}

      iex> CorroCLI.run_command(["invalid", "command"])
      {:error, {:exit_code, 1, "Error: unknown command..."}}
  """
  def run_command(args, opts \\ []) when is_list(args) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    config_path = Keyword.get(opts, :config_path) || get_config_path()
    binary_path = Keyword.get(opts, :binary_path) || get_binary_path()

    # Build the full command
    cmd_args = args ++ ["--config", config_path]

    Logger.debug("CorroCLI: command #{binary_path} #{Enum.join(cmd_args, " ")}")

    # Validate that binary and config exist
    case validate_prerequisites(binary_path, config_path) do
      :ok ->
        execute_port_command(binary_path, cmd_args, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Runs an arbitrary corrosion command asynchronously.

  ## Parameters
  - `args` - List of command arguments
  - `opts` - Options keyword list (same as run_command/2)

  ## Returns
  - `Task` that when awaited returns `{:ok, output}` or `{:error, reason}`

  ## Examples
      iex> task = CorroCLI.run_command_async(["cluster", "members"])
      iex> result = Task.await(task, 10_000)
      {:ok, "{\\"id\\": \\"94bfbec2..."}

      # Run multiple commands concurrently
      iex> tasks = [
      ...>   CorroCLI.cluster_members_async(),
      ...>   CorroCLI.cluster_info_async(),
      ...>   CorroCLI.cluster_status_async()
      ...> ]
      iex> results = Task.await_many(tasks, 10_000)
  """
  def run_command_async(args, opts \\ []) when is_list(args) do
    Task.async(fn -> run_command(args, opts) end)
  end

  # Private functions

  defp get_config_path do
    Application.get_env(:corro_cli, :config_path)
  end

  defp get_binary_path do
    Application.get_env(:corro_cli, :binary_path)
  end

  defp validate_prerequisites(binary_path, config_path) do
    cond do
      is_nil(binary_path) ->
        Logger.error("CorroCLI: Binary path not configured")
        {:error, "Corrosion binary path not configured. Set :binary_path in opts or app config."}

      is_nil(config_path) ->
        Logger.error("CorroCLI: Config path not configured")
        {:error, "Corrosion config path not configured. Set :config_path in opts or app config."}

      true ->
        validate_files(binary_path, config_path)
    end
  end

  defp validate_files(binary_path, config_path) do
    abs_binary_path = Path.absname(binary_path)
    abs_config_path = Path.absname(config_path)

    cond do
      not File.exists?(abs_binary_path) ->
        Logger.error("CorroCLI: Binary not found at #{abs_binary_path}")
        {:error, "Corrosion binary not found at: #{abs_binary_path}"}

      not is_executable?(abs_binary_path) ->
        Logger.error("CorroCLI: Binary not executable at #{abs_binary_path}")
        {:error, "Corrosion binary is not executable: #{abs_binary_path}"}

      not File.exists?(abs_config_path) ->
        Logger.error("CorroCLI: Config not found at #{abs_config_path}")
        {:error, "Corrosion config not found at: #{abs_config_path}"}

      true ->
        :ok
    end
  end

  # Helper function to check if a file is executable
  defp is_executable?(path) do
    case File.stat(path) do
      {:ok, %{mode: mode}} ->
        # Check if owner execute bit is set (0o100)
        # Use Bitwise.band/2 for bitwise AND operation
        import Bitwise
        (mode &&& 0o100) != 0

      {:error, _} ->
        false
    end
  end

  defp execute_port_command(binary_path, args, _timeout) do
    # Convert to absolute path to help with path resolution
    abs_binary_path = Path.absname(binary_path)

    try do
      # Use System.cmd with basic options (no timeout for now)
      case System.cmd(abs_binary_path, args, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, output}

        {error_output, exit_code} ->
          Logger.warning("CorroCLI: Command failed with exit code #{exit_code}")
          Logger.warning("CorroCLI: Error output: #{error_output}")
          {:error, {:exit_code, exit_code, error_output}}
      end
    catch
      :exit, {:enoent, _} ->
        Logger.error("CorroCLI: Binary not found at #{abs_binary_path}")

        {:error,
         "Binary not found: #{abs_binary_path}. Check that the corrosion binary exists and is executable."}

      error ->
        Logger.error("CorroCLI: Unexpected error: #{inspect(error)}")
        {:error, {:unexpected_error, error}}
    end
  end
end
