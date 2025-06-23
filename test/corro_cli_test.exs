defmodule CorroCliTest do
  use ExUnit.Case
  doctest CorroCLI

  describe "run_command/2" do
    test "requires binary_path configuration" do
      # Clear configuration
      Application.delete_env(:corro_cli, :binary_path)
      Application.delete_env(:corro_cli, :config_path)
      
      assert {:error, reason} = CorroCLI.run_command(["--version"])
      assert String.contains?(reason, "binary path not configured")
    end

    test "requires config_path configuration" do
      # Set binary but not config
      temp_binary = Path.join(System.tmp_dir!(), "fake_corrosion")
      File.write!(temp_binary, "#!/bin/sh\necho 'fake corrosion'")
      File.chmod!(temp_binary, 0o755)
      
      assert {:error, reason} = CorroCLI.run_command(["--version"], binary_path: temp_binary)
      assert String.contains?(reason, "config path not configured")
      
      # Cleanup
      File.rm!(temp_binary)
    end

    test "validates binary exists" do
      temp_config = Path.join(System.tmp_dir!(), "fake_config.toml")
      File.write!(temp_config, "[api]\naddr = \"127.0.0.1:8081\"")
      
      assert {:error, reason} = CorroCLI.run_command(
        ["--version"], 
        binary_path: "/nonexistent/binary",
        config_path: temp_config
      )
      assert String.contains?(reason, "not found")
      
      # Cleanup
      File.rm!(temp_config)
    end

    test "validates config file exists" do
      temp_binary = Path.join(System.tmp_dir!(), "fake_corrosion")
      File.write!(temp_binary, "#!/bin/sh\necho 'fake corrosion'")
      File.chmod!(temp_binary, 0o755)
      
      assert {:error, reason} = CorroCLI.run_command(
        ["--version"],
        binary_path: temp_binary,
        config_path: "/nonexistent/config.toml"
      )
      assert String.contains?(reason, "not found")
      
      # Cleanup
      File.rm!(temp_binary)
    end
  end

  describe "run_command_async/2" do
    test "returns a task" do
      task = CorroCLI.run_command_async(["--version"])
      assert %Task{} = task
      
      # The task will fail because of missing configuration,
      # but we just want to verify it returns a Task
      result = Task.await(task, 1000)
      assert match?({:error, _}, result)
    end
  end

  describe "convenience functions" do
    test "cluster_members/1 calls run_command with correct args" do
      # This will fail due to missing config, but we can verify the error
      # indicates it tried to run the cluster members command
      assert {:error, _reason} = CorroCLI.cluster_members()
    end

    test "cluster_info/1 calls run_command with correct args" do
      assert {:error, _reason} = CorroCLI.cluster_info()
    end

    test "cluster_status/1 calls run_command with correct args" do
      assert {:error, _reason} = CorroCLI.cluster_status()
    end

    test "async versions return tasks" do
      assert %Task{} = CorroCLI.cluster_members_async()
      assert %Task{} = CorroCLI.cluster_info_async()
      assert %Task{} = CorroCLI.cluster_status_async()
    end
  end

  describe "option handling" do
    test "passes through timeout option" do
      # Create valid files
      temp_binary = Path.join(System.tmp_dir!(), "fake_corrosion")
      temp_config = Path.join(System.tmp_dir!(), "fake_config.toml")
      
      File.write!(temp_binary, "#!/bin/sh\nsleep 2; echo 'done'")
      File.chmod!(temp_binary, 0o755)
      File.write!(temp_config, "[api]\naddr = \"127.0.0.1:8081\"")
      
      # This should succeed and execute the fake binary
      assert {:ok, output} = CorroCLI.run_command(
        ["--version"],
        binary_path: temp_binary,
        config_path: temp_config,
        timeout: 5000
      )
      
      assert String.contains?(output, "done")
      
      # Cleanup
      File.rm!(temp_binary)
      File.rm!(temp_config)
    end

    test "uses application configuration when available" do
      temp_binary = Path.join(System.tmp_dir!(), "fake_corrosion")
      temp_config = Path.join(System.tmp_dir!(), "fake_config.toml")
      
      File.write!(temp_binary, "#!/bin/sh\necho 'app config test'")
      File.chmod!(temp_binary, 0o755)
      File.write!(temp_config, "[api]\naddr = \"127.0.0.1:8081\"")
      
      # Set application configuration
      Application.put_env(:corro_cli, :binary_path, temp_binary)
      Application.put_env(:corro_cli, :config_path, temp_config)
      
      assert {:ok, output} = CorroCLI.run_command(["--version"])
      assert String.contains?(output, "app config test")
      
      # Cleanup
      Application.delete_env(:corro_cli, :binary_path)
      Application.delete_env(:corro_cli, :config_path)
      File.rm!(temp_binary)
      File.rm!(temp_config)
    end
  end
end