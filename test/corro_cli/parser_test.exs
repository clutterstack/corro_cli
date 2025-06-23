defmodule CorroCLI.ParserTest do
  use ExUnit.Case
  doctest CorroCLI.Parser

  alias CorroCLI.Parser

  describe "parse_json_output/2" do
    test "parses empty string" do
      assert {:ok, []} = Parser.parse_json_output("")
    end

    test "parses nil input" do
      assert {:ok, []} = Parser.parse_json_output(nil)
    end

    test "parses single JSON object" do
      json = ~s({"id": "abc123", "state": {"addr": "127.0.0.1:8787"}})
      assert {:ok, [object]} = Parser.parse_json_output(json)
      assert object["id"] == "abc123"
      assert get_in(object, ["state", "addr"]) == "127.0.0.1:8787"
    end

    test "parses JSON array" do
      json = ~s([{"id": "abc123"}, {"id": "def456"}])
      assert {:ok, objects} = Parser.parse_json_output(json)
      assert length(objects) == 2
      assert Enum.at(objects, 0)["id"] == "abc123"
      assert Enum.at(objects, 1)["id"] == "def456"
    end

    test "parses concatenated JSON objects" do
      json = ~s({"id": "abc123", "state": {"addr": "127.0.0.1:8787"}}\n{"id": "def456", "state": {"addr": "127.0.0.1:8788"}})
      assert {:ok, objects} = Parser.parse_json_output(json)
      assert length(objects) == 2
      assert Enum.at(objects, 0)["id"] == "abc123"
      assert Enum.at(objects, 1)["id"] == "def456"
    end

    test "parses concatenated JSON objects with whitespace" do
      json = ~s({"id": "abc123"}   \n\n   {"id": "def456"})
      assert {:ok, objects} = Parser.parse_json_output(json)
      assert length(objects) == 2
      assert Enum.at(objects, 0)["id"] == "abc123"
      assert Enum.at(objects, 1)["id"] == "def456"
    end

    test "handles invalid JSON" do
      json = ~s({"invalid": json})
      assert {:error, {:parse_error, _, _}} = Parser.parse_json_output(json)
    end

    test "applies enhancer function" do
      json = ~s({"id": "abc123"})
      enhancer = fn obj -> Map.put(obj, "enhanced", true) end
      assert {:ok, [object]} = Parser.parse_json_output(json, enhancer)
      assert object["enhanced"] == true
    end
  end

  describe "parse_cluster_members/1" do
    test "parses empty cluster members output" do
      assert {:ok, []} = Parser.parse_cluster_members("")
      assert {:ok, []} = Parser.parse_cluster_members(nil)
    end

    test "parses single cluster member" do
      json = ~s({"id": "abc123", "state": {"addr": "127.0.0.1:8787", "last_sync_ts": 1234567890}})
      assert {:ok, [member]} = Parser.parse_cluster_members(json)
      
      # Check that display fields are added
      assert member["display_id"] == "abc123"
      assert member["display_addr"] == "127.0.0.1:8787"
      assert member["display_status"] == "active"
      assert is_binary(member["display_status_class"])
    end

    test "parses multiple cluster members" do
      json = ~s({"id": "abc123", "state": {"addr": "127.0.0.1:8787"}}\n{"id": "def456", "state": {"addr": "127.0.0.1:8788"}})
      assert {:ok, members} = Parser.parse_cluster_members(json)
      assert length(members) == 2
      
      # Both should have display fields
      Enum.each(members, fn member ->
        assert is_binary(member["display_id"])
        assert is_binary(member["display_addr"])
        assert is_binary(member["display_status"])
      end)
    end
  end

  describe "extract_region_from_node_id/1" do
    test "extracts region from region-machine format" do
      assert Parser.extract_region_from_node_id("ams-machine123") == "ams"
      assert Parser.extract_region_from_node_id("fra-xyz456") == "fra"
    end

    test "handles development node format" do
      assert Parser.extract_region_from_node_id("node1") == "dev"
      assert Parser.extract_region_from_node_id("node123") == "dev"
    end

    test "handles unknown formats" do
      assert Parser.extract_region_from_node_id("unknown-format") == "unknown"
      assert Parser.extract_region_from_node_id("invalidformat") == "unknown"
      assert Parser.extract_region_from_node_id(nil) == "unknown"
      assert Parser.extract_region_from_node_id(123) == "unknown"
    end
  end

  describe "active_member?/1" do
    test "identifies active member with recent sync" do
      recent_timestamp = (DateTime.utc_now() |> DateTime.to_unix(:nanosecond)) - 60_000_000_000 # 1 minute ago
      
      member = %{
        "state" => %{
          "last_sync_ts" => recent_timestamp,
          "addr" => "127.0.0.1:8787"
        }
      }
      
      assert Parser.active_member?(member) == true
    end

    test "identifies inactive member with old sync" do
      old_timestamp = (DateTime.utc_now() |> DateTime.to_unix(:nanosecond)) - 600_000_000_000 # 10 minutes ago
      
      member = %{
        "state" => %{
          "last_sync_ts" => old_timestamp,
          "addr" => "127.0.0.1:8787"
        }
      }
      
      assert Parser.active_member?(member) == false
    end

    test "identifies inactive member without address" do
      recent_timestamp = (DateTime.utc_now() |> DateTime.to_unix(:nanosecond)) - 60_000_000_000
      
      member = %{
        "state" => %{
          "last_sync_ts" => recent_timestamp
          # no addr field
        }
      }
      
      assert Parser.active_member?(member) == false
    end

    test "identifies inactive member without sync timestamp" do
      member = %{
        "state" => %{
          "addr" => "127.0.0.1:8787"
          # no last_sync_ts
        }
      }
      
      assert Parser.active_member?(member) == false
    end
  end

  describe "summarize_member/1" do
    test "creates member summary" do
      member = %{
        "display_id" => "abc123",
        "display_addr" => "127.0.0.1:8787",
        "display_status" => "active",
        "display_cluster_id" => "cluster1",
        "display_ring" => "ring1",
        "display_last_sync" => "2025-01-01 12:00:00 UTC",
        "display_rtt_avg" => 12.5,
        "display_rtt_count" => 10
      }
      
      summary = Parser.summarize_member(member)
      
      assert summary.id == "abc123"
      assert summary.address == "127.0.0.1:8787"
      assert summary.status == "active"
      assert summary.cluster_id == "cluster1"
      assert summary.ring == "ring1"
      assert summary.last_sync == "2025-01-01 12:00:00 UTC"
      assert summary.avg_rtt == 12.5
      assert summary.rtt_samples == 10
    end
  end
end