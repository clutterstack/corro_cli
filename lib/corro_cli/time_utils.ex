defmodule CorroCLI.TimeUtils do
  @moduledoc """
  Utilities for handling Corrosion timestamps.

  Corrosion uses the uhlc library's NTP64 format for timestamps, which is:
  - 64-bit fixed-point number
  - Upper 32 bits: seconds since Unix epoch (January 1, 1970) 
  - Lower 32 bits: fractional seconds (1 unit = 1/2^32 seconds)

  Note: Despite the "NTP64" name, uhlc uses Unix epoch, not NTP epoch.

  ## Examples

      iex> CorroCLI.TimeUtils.format_corrosion_timestamp(7517054269677675168)
      "2025-06-17 22:49:43 UTC"

      iex> CorroCLI.TimeUtils.format_corrosion_timestamp(nil)
      "Never"
  """

  @doc """
  Formats a Corrosion timestamp (uhlc NTP64 format) to readable format.

  Corrosion uses the uhlc library's NTP64 format, which is:
  - 64-bit fixed-point number
  - Upper 32 bits: seconds since Unix epoch (January 1, 1970)
  - Lower 32 bits: fractional seconds (1 unit = 1/2^32 seconds)

  Note: Despite the "NTP64" name, uhlc uses Unix epoch, not NTP epoch.

  ## Parameters
  - `ntp64_timestamp` - 64-bit integer timestamp from Corrosion

  ## Returns
  - Formatted timestamp string in "YYYY-MM-DD HH:MM:SS UTC" format
  - "Never" for nil input
  - "Invalid timestamp" for invalid input

  ## Examples
      iex> CorroCLI.TimeUtils.format_corrosion_timestamp(7517054269677675168)
      "2025-06-17 22:49:43 UTC"

      iex> CorroCLI.TimeUtils.format_corrosion_timestamp(nil)
      "Never"

      iex> CorroCLI.TimeUtils.format_corrosion_timestamp("invalid")
      "Invalid timestamp"
  """
  def format_corrosion_timestamp(nil), do: "Never"

  def format_corrosion_timestamp(ntp64_timestamp) when is_integer(ntp64_timestamp) do
    import Bitwise

    # uhlc's NTP64 is a 64-bit fixed-point number:
    # Upper 32 bits: seconds since Unix epoch (Jan 1, 1970)
    # Lower 32 bits: fractional seconds

    # Extract the seconds part (upper 32 bits)
    unix_seconds = ntp64_timestamp >>> 32

    # Extract the fractional part (lower 32 bits)
    ntp_fraction = ntp64_timestamp &&& 0xFFFFFFFF

    # Convert fractional part to microseconds for DateTime
    # ntp_fraction * 1_000_000 / 2^32
    microseconds = div(ntp_fraction * 1_000_000, 4_294_967_296)

    case DateTime.from_unix(unix_seconds, :second) do
      {:ok, datetime} ->
        # Add microseconds for sub-second precision
        datetime_with_precision = %{datetime | microsecond: {microseconds, 6}}
        Calendar.strftime(datetime_with_precision, "%Y-%m-%d %H:%M:%S UTC")

      {:error, _} ->
        "Invalid timestamp"
    end
  end

  def format_corrosion_timestamp(_), do: "Invalid timestamp"

  @doc """
  Converts a Corrosion NTP64 timestamp to an Elixir DateTime struct.

  ## Parameters
  - `ntp64_timestamp` - 64-bit integer timestamp from Corrosion

  ## Returns
  - `{:ok, datetime}` - DateTime struct with microsecond precision
  - `{:error, reason}` - Error details

  ## Examples
      iex> {:ok, dt} = CorroCLI.TimeUtils.parse_corrosion_timestamp(7517054269677675168)
      iex> dt.year
      2025
  """
  def parse_corrosion_timestamp(nil), do: {:error, :nil_timestamp}

  def parse_corrosion_timestamp(ntp64_timestamp) when is_integer(ntp64_timestamp) do
    import Bitwise

    # Extract the seconds part (upper 32 bits)
    unix_seconds = ntp64_timestamp >>> 32

    # Extract the fractional part (lower 32 bits)
    ntp_fraction = ntp64_timestamp &&& 0xFFFFFFFF

    # Convert fractional part to microseconds for DateTime
    microseconds = div(ntp_fraction * 1_000_000, 4_294_967_296)

    case DateTime.from_unix(unix_seconds, :second) do
      {:ok, datetime} ->
        # Add microseconds for sub-second precision
        datetime_with_precision = %{datetime | microsecond: {microseconds, 6}}
        {:ok, datetime_with_precision}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def parse_corrosion_timestamp(_), do: {:error, :invalid_format}

  @doc """
  Checks if a Corrosion timestamp is recent (within specified seconds).

  ## Parameters
  - `ntp64_timestamp` - 64-bit integer timestamp from Corrosion
  - `seconds` - Number of seconds to consider "recent" (default: 300 = 5 minutes)

  ## Returns
  - `true` if timestamp is within the specified timeframe
  - `false` if timestamp is older or invalid

  ## Examples
      iex> recent_timestamp = System.system_time(:nanosecond) |> CorroCLI.TimeUtils.to_corrosion_timestamp()
      iex> CorroCLI.TimeUtils.recent?(recent_timestamp, 60)
      true
  """
  def recent?(ntp64_timestamp, seconds \\ 300) when is_integer(seconds) and seconds > 0 do
    case parse_corrosion_timestamp(ntp64_timestamp) do
      {:ok, datetime} ->
        now = DateTime.utc_now()
        diff = DateTime.diff(now, datetime, :second)
        diff <= seconds

      {:error, _} ->
        false
    end
  end

  @doc """
  Converts an Elixir DateTime to a Corrosion NTP64 timestamp.

  This is useful for testing or when you need to create timestamps compatible
  with Corrosion.

  ## Parameters
  - `datetime` - DateTime struct to convert

  ## Returns
  - 64-bit integer in NTP64 format

  ## Examples
      iex> dt = DateTime.from_naive!(~N[2025-06-17 22:49:43.123456], "Etc/UTC")
      iex> timestamp = CorroCLI.TimeUtils.to_corrosion_timestamp(dt)
      iex> is_integer(timestamp)
      true
  """
  def to_corrosion_timestamp(%DateTime{} = datetime) do
    import Bitwise

    # Convert to Unix timestamp
    unix_seconds = DateTime.to_unix(datetime, :second)
    {microseconds, _precision} = datetime.microsecond

    # Convert microseconds to NTP fraction
    # ntp_fraction = microseconds * 2^32 / 1_000_000
    ntp_fraction = div(microseconds * 4_294_967_296, 1_000_000)

    # Combine seconds and fraction
    (unix_seconds <<< 32) ||| ntp_fraction
  end

  @doc """
  Converts current system time to a Corrosion NTP64 timestamp.

  ## Returns
  - 64-bit integer representing current time in NTP64 format

  ## Examples
      iex> timestamp = CorroCLI.TimeUtils.now_as_corrosion_timestamp()
      iex> is_integer(timestamp)
      true
  """
  def now_as_corrosion_timestamp do
    DateTime.utc_now() |> to_corrosion_timestamp()
  end
end