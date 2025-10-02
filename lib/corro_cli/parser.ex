defmodule CorroCLI.Parser do
  @moduledoc """
  Parses output from various Corrosion CLI commands.

  Handles the concatenated JSON format that Corrosion uses for structured output
  from commands like `cluster members`, `cluster info`, etc. This format consists
  of multiple JSON objects concatenated together, often separated by whitespace.

  Also properly handles single-node setups where CLI commands return empty results.

  ## Supported Formats

  1. **Single JSON object**: `{"id": "abc123", "state": {...}}`
  2. **JSON array**: `[{"id": "abc123"}, {"id": "def456"}]`
  3. **Concatenated JSON objects**: `{"id": "abc123"}\n{"id": "def456"}`

  ## Examples

      # Parse cluster members output
      output = ~s({"id":"abc123","state":{"addr":"127.0.0.1:8787"}}\n{"id":"def456","state":{"addr":"127.0.0.1:8788"}})
      {:ok, members} = CorroCLI.Parser.parse_cluster_members(output)

      # Parse any concatenated JSON output
      {:ok, objects} = CorroCLI.Parser.parse_json_output(output)
  """

  require Logger

  @doc """
  Parses cluster members output into a structured format.

  ## Parameters
  - `cli_output` - Raw concatenated JSON string output from `corrosion cluster members`

  ## Returns
  - `{:ok, members}` - List of parsed member maps straight from the CLI JSON
  - `{:error, reason}` - Parse error details

  ## Examples
      iex> output = ~s({"id":"abc123","state":{"addr":"127.0.0.1:8787"}}\n{"id":"def456","state":{"addr":"127.0.0.1:8788"}})
      iex> CorroCLI.Parser.parse_cluster_members(output)
      {:ok, [%{"id" => "abc123", "state" => %{"addr" => "127.0.0.1:8787"}}, ...]}

      # Single node case
      iex> CorroCLI.Parser.parse_cluster_members("")
      {:ok, []}
  """
  def parse_cluster_members(cli_output) when is_binary(cli_output) do
    parse_json_output(cli_output)
  end

  # Handle nil input (can happen with some CLI error cases)
  def parse_cluster_members(nil) do
    Logger.debug("CorroCLI.Parser: Received nil input for cluster members")
    {:ok, []}
  end

  @doc """
  Parses cluster info output.

  ## Parameters
  - `cli_output` - Raw concatenated JSON string output from `corrosion cluster info`

  ## Returns
  - `{:ok, info}` - Parsed cluster info
  - `{:error, reason}` - Parse error details
  """
  def parse_cluster_info(cli_output) when is_binary(cli_output) do
    parse_json_output(cli_output)
  end

  def parse_cluster_info(nil) do
    Logger.debug("CorroCLI.Parser: Received nil input for cluster info")
    {:ok, []}
  end

  @doc """
  Parses cluster status output.
  """
  def parse_cluster_status(cli_output) when is_binary(cli_output) do
    parse_json_output(cli_output)
  end

  def parse_cluster_status(nil) do
    Logger.debug("CorroCLI.Parser: Received nil input for cluster status")
    {:ok, []}
  end

  @doc """
  Parses concatenated JSON objects from corrosion command output.

  This is the core parsing function that handles:
  1. Single JSON objects
  2. JSON arrays
  3. Multiple JSON objects concatenated together

  ## Parameters
  - `output` - Raw string output from corrosion CLI
  - `enhancer_fun` - Optional function to enhance each parsed object (default: identity)

  ## Returns
  - `{:ok, objects}` - List of parsed objects
  - `{:error, reason}` - Parse error details
  """
  def parse_json_output(output, enhancer_fun \\ &Function.identity/1)

  def parse_json_output(output, _enhancer_fun) when output in [nil, ""] do
    {:ok, []}
  end

  def parse_json_output(output, enhancer_fun) when is_binary(output) do
    output
    |> String.trim()
    |> case do
      "" -> {:ok, []}
      trimmed -> parse_json_objects(trimmed, enhancer_fun)
    end
  end

  defp parse_json_objects(output, enhancer_fun) do
    # Try parsing as a single JSON first (most common case)
    case Jason.decode(output) do
      {:ok, object} when is_map(object) ->
        {:ok, [enhancer_fun.(object)]}

      {:ok, array} when is_list(array) ->
        {:ok, Enum.map(array, enhancer_fun)}

      {:error, _} ->
        # Fall back to splitting concatenated objects
        parse_concatenated_objects(output, enhancer_fun)
    end
  end

  defp parse_concatenated_objects(output, enhancer_fun) do
    # Split on pattern that separates complete JSON objects
    # This regex looks for } followed by optional whitespace followed by {
    output
    |> String.split(~r/(?<=\})\s*(?=\{)/)
    |> Enum.reduce_while([], fn chunk, acc ->
      case Jason.decode(String.trim(chunk)) do
        {:ok, object} when is_map(object) ->
          {:cont, [enhancer_fun.(object) | acc]}

        {:error, reason} ->
          {:halt, {:error, {:parse_error, chunk, reason}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      objects -> {:ok, Enum.reverse(objects)}
    end
  end

end
