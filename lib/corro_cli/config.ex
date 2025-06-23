defmodule CorroCLI.Config do
  @moduledoc """
  Configuration management for Corrosion CLI operations.

  This module provides utilities for managing Corrosion binary and configuration
  file paths, with support for various deployment scenarios including development,
  production, and containerized environments.

  ## Configuration Sources

  Configuration is resolved in the following order (first found wins):

  1. **Function options** - Passed directly to CLI functions
  2. **Application environment** - `:corro_cli` application config
  3. **System environment variables** - `CORROSION_BINARY_PATH`, `CORROSION_CONFIG_PATH`
  4. **Default paths** - Common installation locations

  ## Application Configuration

      config :corro_cli,
        binary_path: "/usr/local/bin/corrosion",
        config_path: "/etc/corrosion/config.toml",
        timeout: 10_000

  ## Environment Variables

  - `CORROSION_BINARY_PATH` - Path to corrosion binary
  - `CORROSION_CONFIG_PATH` - Path to corrosion config file
  - `CORROSION_TIMEOUT` - Default timeout in milliseconds

  ## Examples

      # Get configured binary path
      {:ok, path} = CorroCLI.Config.get_binary_path()

      # Validate configuration
      :ok = CorroCLI.Config.validate()

      # Get all configuration as a map
      config = CorroCLI.Config.get_config()
  """

  require Logger

  @default_timeout 5_000
  @default_binary_paths [
    # Common installation paths
    "/usr/local/bin/corrosion",
    "/usr/bin/corrosion", 
    "./corrosion",
    # Development paths
    "./corrosion/corrosion",
    "./corrosion/corrosion-mac",
    "./corrosion-mac"
  ]

  @doc """
  Gets the configured Corrosion binary path.

  Resolves path from configuration sources in priority order.

  ## Returns
  - `{:ok, path}` - Valid binary path
  - `{:error, reason}` - Path not found or not configured

  ## Examples
      iex> CorroCLI.Config.get_binary_path()
      {:ok, "/usr/local/bin/corrosion"}
  """
  def get_binary_path do
    case resolve_binary_path() do
      path when is_binary(path) ->
        {:ok, path}

      nil ->
        {:error, "Corrosion binary path not configured. Set via app config, environment variable CORROSION_BINARY_PATH, or function options."}
    end
  end

  @doc """
  Gets the configured Corrosion config file path.

  ## Returns
  - `{:ok, path}` - Valid config path
  - `{:error, reason}` - Path not found or not configured

  ## Examples
      iex> CorroCLI.Config.get_config_path()
      {:ok, "/etc/corrosion/config.toml"}
  """
  def get_config_path do
    case resolve_config_path() do
      path when is_binary(path) ->
        {:ok, path}

      nil ->
        {:error, "Corrosion config path not configured. Set via app config, environment variable CORROSION_CONFIG_PATH, or function options."}
    end
  end

  @doc """
  Gets the configured timeout value.

  ## Returns
  - Timeout in milliseconds (integer)

  ## Examples
      iex> CorroCLI.Config.get_timeout()
      5000
  """
  def get_timeout do
    Application.get_env(:corro_cli, :timeout) ||
      parse_env_timeout() ||
      @default_timeout
  end

  @doc """
  Gets all configuration as a map.

  ## Returns
  - Map with `:binary_path`, `:config_path`, and `:timeout` keys

  ## Examples
      iex> CorroCLI.Config.get_config()
      %{
        binary_path: {:ok, "/usr/local/bin/corrosion"},
        config_path: {:ok, "/etc/corrosion/config.toml"},
        timeout: 5000
      }
  """
  def get_config do
    %{
      binary_path: get_binary_path(),
      config_path: get_config_path(),
      timeout: get_timeout()
    }
  end

  @doc """
  Validates the current configuration.

  Checks that binary and config files exist and are accessible.

  ## Returns
  - `:ok` - Configuration is valid
  - `{:error, [reasons]}` - List of validation errors

  ## Examples
      iex> CorroCLI.Config.validate()
      :ok

      iex> CorroCLI.Config.validate()
      {:error, ["Binary not found: /usr/local/bin/corrosion", "Config not readable: /etc/corrosion/config.toml"]}
  """
  def validate do
    errors = []

    errors =
      case get_binary_path() do
        {:ok, binary_path} ->
          case validate_binary(binary_path) do
            :ok -> errors
            {:error, reason} -> [reason | errors]
          end

        {:error, reason} ->
          [reason | errors]
      end

    errors =
      case get_config_path() do
        {:ok, config_path} ->
          case validate_config_file(config_path) do
            :ok -> errors
            {:error, reason} -> [reason | errors]
          end

        {:error, reason} ->
          [reason | errors]
      end

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Validates that a binary path exists and is executable.

  ## Parameters
  - `binary_path` - Path to corrosion binary

  ## Returns
  - `:ok` - Binary is valid
  - `{:error, reason}` - Validation error

  ## Examples
      iex> CorroCLI.Config.validate_binary("/usr/local/bin/corrosion")
      :ok
  """
  def validate_binary(binary_path) when is_binary(binary_path) do
    abs_path = Path.absname(binary_path)

    cond do
      not File.exists?(abs_path) ->
        {:error, "Binary not found: #{abs_path}"}

      not is_executable?(abs_path) ->
        {:error, "Binary not executable: #{abs_path}"}

      true ->
        :ok
    end
  end

  @doc """
  Validates that a config file exists and is readable.

  ## Parameters
  - `config_path` - Path to corrosion config file

  ## Returns
  - `:ok` - Config file is valid
  - `{:error, reason}` - Validation error

  ## Examples
      iex> CorroCLI.Config.validate_config_file("/etc/corrosion/config.toml")
      :ok
  """
  def validate_config_file(config_path) when is_binary(config_path) do
    abs_path = Path.absname(config_path)

    cond do
      not File.exists?(abs_path) ->
        {:error, "Config file not found: #{abs_path}"}

      not File.regular?(abs_path) ->
        {:error, "Config path is not a file: #{abs_path}"}

      not readable?(abs_path) ->
        {:error, "Config file not readable: #{abs_path}"}

      true ->
        :ok
    end
  end

  @doc """
  Discovers corrosion binary in common installation locations.

  ## Returns
  - `{:ok, path}` - Found binary path
  - `{:error, :not_found}` - No binary found in common locations

  ## Examples
      iex> CorroCLI.Config.discover_binary()
      {:ok, "/usr/local/bin/corrosion"}
  """
  def discover_binary do
    case Enum.find(@default_binary_paths, &(File.exists?(&1) and is_executable?(&1))) do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  # Private functions

  defp resolve_binary_path do
    Application.get_env(:corro_cli, :binary_path) ||
      System.get_env("CORROSION_BINARY_PATH") ||
      case discover_binary() do
        {:ok, path} -> path
        {:error, :not_found} -> nil
      end
  end

  defp resolve_config_path do
    Application.get_env(:corro_cli, :config_path) ||
      System.get_env("CORROSION_CONFIG_PATH")
  end

  defp parse_env_timeout do
    case System.get_env("CORROSION_TIMEOUT") do
      nil -> nil
      value ->
        case Integer.parse(value) do
          {timeout, _} when timeout > 0 -> timeout
          _ -> nil
        end
    end
  end

  defp is_executable?(path) do
    case File.stat(path) do
      {:ok, %{mode: mode}} ->
        # Check if owner execute bit is set (0o100)
        import Bitwise
        (mode &&& 0o100) != 0

      {:error, _} ->
        false
    end
  end

  defp readable?(path) do
    case File.read(path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
end