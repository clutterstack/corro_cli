defmodule CorroCLI.TimeUtilsTest do
  use ExUnit.Case
  doctest CorroCLI.TimeUtils

  alias CorroCLI.TimeUtils

  describe "format_corrosion_timestamp/1" do
    test "formats nil as Never" do
      assert TimeUtils.format_corrosion_timestamp(nil) == "Never"
    end

    test "formats invalid input" do
      assert TimeUtils.format_corrosion_timestamp("invalid") == "Invalid timestamp"
      assert TimeUtils.format_corrosion_timestamp(%{}) == "Invalid timestamp"
    end

    test "formats valid NTP64 timestamp" do
      # This represents roughly 2025-06-17 22:49:43 UTC
      timestamp = 7517054269677675168
      formatted = TimeUtils.format_corrosion_timestamp(timestamp)
      
      # Should be in YYYY-MM-DD HH:MM:SS UTC format
      assert formatted =~ ~r/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/
      assert String.contains?(formatted, "2025")
    end

    test "handles zero timestamp" do
      # Timestamp 0 should format to Unix epoch
      formatted = TimeUtils.format_corrosion_timestamp(0)
      assert formatted == "1970-01-01 00:00:00 UTC"
    end
  end

  describe "parse_corrosion_timestamp/1" do
    test "parses nil input" do
      assert TimeUtils.parse_corrosion_timestamp(nil) == {:error, :nil_timestamp}
    end

    test "parses invalid input" do
      assert TimeUtils.parse_corrosion_timestamp("invalid") == {:error, :invalid_format}
      assert TimeUtils.parse_corrosion_timestamp(%{}) == {:error, :invalid_format}
    end

    test "parses valid NTP64 timestamp" do
      timestamp = 7517054269677675168
      assert {:ok, datetime} = TimeUtils.parse_corrosion_timestamp(timestamp)
      
      assert %DateTime{} = datetime
      assert datetime.year == 2025
      assert datetime.month == 6
      # Microsecond precision should be preserved
      assert is_tuple(datetime.microsecond)
    end

    test "parses zero timestamp to Unix epoch" do
      assert {:ok, datetime} = TimeUtils.parse_corrosion_timestamp(0)
      assert datetime.year == 1970
      assert datetime.month == 1
      assert datetime.day == 1
    end
  end

  describe "to_corrosion_timestamp/1 and parse_corrosion_timestamp/1 roundtrip" do
    test "roundtrip conversion preserves datetime" do
      original_dt = DateTime.from_naive!(~N[2025-06-17 22:49:43.123456], "Etc/UTC")
      
      # Convert to corrosion timestamp and back
      timestamp = TimeUtils.to_corrosion_timestamp(original_dt)
      assert {:ok, parsed_dt} = TimeUtils.parse_corrosion_timestamp(timestamp)
      
      # Should be very close (within microsecond precision)
      diff = DateTime.diff(original_dt, parsed_dt, :microsecond)
      assert abs(diff) < 1000  # Allow small rounding differences
    end
  end

  describe "recent?/2" do
    test "identifies recent timestamp" do
      # Create a timestamp from 30 seconds ago
      thirty_seconds_ago = DateTime.utc_now() 
                          |> DateTime.add(-30, :second)
                          |> TimeUtils.to_corrosion_timestamp()
      
      assert TimeUtils.recent?(thirty_seconds_ago, 60) == true
    end

    test "identifies old timestamp" do
      # Create a timestamp from 10 minutes ago
      ten_minutes_ago = DateTime.utc_now()
                       |> DateTime.add(-600, :second)
                       |> TimeUtils.to_corrosion_timestamp()
      
      assert TimeUtils.recent?(ten_minutes_ago, 300) == false
    end

    test "handles invalid timestamp" do
      assert TimeUtils.recent?("invalid", 60) == false
      assert TimeUtils.recent?(nil, 60) == false
    end

    test "uses default window of 5 minutes" do
      # Create a timestamp from 3 minutes ago
      three_minutes_ago = DateTime.utc_now()
                         |> DateTime.add(-180, :second)
                         |> TimeUtils.to_corrosion_timestamp()
      
      assert TimeUtils.recent?(three_minutes_ago) == true
      
      # Create a timestamp from 7 minutes ago
      seven_minutes_ago = DateTime.utc_now()
                         |> DateTime.add(-420, :second)
                         |> TimeUtils.to_corrosion_timestamp()
      
      assert TimeUtils.recent?(seven_minutes_ago) == false
    end
  end

  describe "now_as_corrosion_timestamp/0" do
    test "returns current time as corrosion timestamp" do
      timestamp = TimeUtils.now_as_corrosion_timestamp()
      
      assert is_integer(timestamp)
      assert timestamp > 0
      
      # Should be very recent
      assert TimeUtils.recent?(timestamp, 5) == true
    end
  end

  describe "to_corrosion_timestamp/1" do
    test "converts DateTime to NTP64 format" do
      dt = DateTime.from_naive!(~N[2025-06-17 22:49:43.123456], "Etc/UTC")
      timestamp = TimeUtils.to_corrosion_timestamp(dt)
      
      assert is_integer(timestamp)
      assert timestamp > 0
      
      # The upper 32 bits should represent the Unix timestamp
      import Bitwise
      unix_seconds = timestamp >>> 32
      expected_unix = DateTime.to_unix(dt, :second)
      
      assert unix_seconds == expected_unix
    end
  end
end