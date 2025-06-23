defmodule CorroCLI.ConfigTest do
  use ExUnit.Case
  doctest CorroCLI.Config

  alias CorroCLI.Config

  describe "get_timeout/0" do
    test "returns default timeout when not configured" do
      # Ensure no app config is set
      Application.delete_env(:corro_cli, :timeout)
      
      timeout = Config.get_timeout()
      assert is_integer(timeout)
      assert timeout > 0
    end
  end

  describe "validate_binary/1" do
    test "validates non-existent binary" do
      assert {:error, reason} = Config.validate_binary("/path/that/does/not/exist")
      assert String.contains?(reason, "not found")
    end

    test "validates existing non-executable file" do
      # Create a temporary non-executable file
      temp_file = Path.join(System.tmp_dir!(), "test_binary_#{:rand.uniform(10000)}")
      File.write!(temp_file, "#!/bin/sh\necho hello")
      
      # Remove execute permissions
      File.chmod!(temp_file, 0o644)
      
      assert {:error, reason} = Config.validate_binary(temp_file)
      assert String.contains?(reason, "not executable")
      
      # Cleanup
      File.rm!(temp_file)
    end
  end

  describe "validate_config_file/1" do
    test "validates non-existent config file" do
      assert {:error, reason} = Config.validate_config_file("/path/that/does/not/exist.toml")
      assert String.contains?(reason, "not found")
    end

    test "validates existing config file" do
      # Create a temporary config file
      temp_file = Path.join(System.tmp_dir!(), "test_config_#{:rand.uniform(10000)}.toml")
      File.write!(temp_file, "[api]\naddr = \"127.0.0.1:8081\"")
      
      assert :ok = Config.validate_config_file(temp_file)
      
      # Cleanup
      File.rm!(temp_file)
    end

    test "validates directory instead of file" do
      temp_dir = Path.join(System.tmp_dir!(), "test_dir_#{:rand.uniform(10000)}")
      File.mkdir!(temp_dir)
      
      assert {:error, reason} = Config.validate_config_file(temp_dir)
      assert String.contains?(reason, "not a file")
      
      # Cleanup
      File.rmdir!(temp_dir)
    end
  end

  describe "discover_binary/0" do
    test "returns error when no binary found" do
      # This test assumes no corrosion binary is installed in standard locations
      # In a real environment, this might find an actual binary
      result = Config.discover_binary()
      
      case result do
        {:ok, path} ->
          # If a binary is found, it should be a valid path
          assert is_binary(path)
          assert File.exists?(path)
        
        {:error, :not_found} ->
          # This is expected in most test environments
          assert true
      end
    end
  end

  describe "get_config/0" do
    test "returns configuration map" do
      config = Config.get_config()
      
      assert is_map(config)
      assert Map.has_key?(config, :binary_path)
      assert Map.has_key?(config, :config_path)
      assert Map.has_key?(config, :timeout)
      
      # Timeout should always be available
      assert is_integer(config.timeout)
      
      # Paths might be ok or error tuples
      assert match?({:ok, _} | {:error, _}, config.binary_path)
      assert match?({:ok, _} | {:error, _}, config.config_path)
    end
  end

  describe "validate/0" do
    test "returns errors when nothing is configured" do
      # Clear any existing config
      Application.delete_env(:corro_cli, :binary_path)
      Application.delete_env(:corro_cli, :config_path)
      
      case Config.validate() do
        :ok ->
          # This can happen if corrosion is actually installed
          assert true
        
        {:error, errors} ->
          assert is_list(errors)
          assert length(errors) > 0
          
          # Should have errors about missing configuration
          error_text = Enum.join(errors, " ")
          assert String.contains?(error_text, "not configured") or 
                 String.contains?(error_text, "not found")
      end
    end
  end
end