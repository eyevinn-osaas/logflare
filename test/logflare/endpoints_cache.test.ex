defmodule Logflare.EndpointsCacheTest do
  use Logflare.DataCase

  alias Logflare.Endpoints

  describe "cache behavior" do
    setup do
      user = insert(:user)

      endpoint =
        insert(:endpoint,
          user: user,
          query: "select current_datetime() as testing",
          proactive_requerying_seconds: 1,
          cache_duration_seconds: 1
        )

      _plan = insert(:plan, name: "Free")

      %{user: user, endpoint: endpoint}
    end

    test "cache starts and serves cached results", %{endpoint: endpoint} do
      # Mock response by setting up test backend
      test_response = [%{"testing" => "123"}]

      GoogleApi.BigQuery.V2.Api.Jobs
      |> expect(:bigquery_jobs_query, 1, fn _conn, _proj_id, _opts ->
        {:ok, TestUtils.gen_bq_response(test_response)}
      end)

      # Start cache process
      {:ok, cache_pid} = start_supervised({Logflare.Endpoints.Cache, {endpoint, %{}}})
      assert Process.alive?(cache_pid)

      # First query should hit backend
      assert {:ok, %{rows: [%{"testing" => "123"}]}} = Endpoints.run_cached_query(endpoint)

      # Second query should hit cache without calling backend again
      assert {:ok, %{rows: [%{"testing" => "123"}]}} = Endpoints.run_cached_query(endpoint)
    end

    test "cache dies on timeout error from query", %{endpoint: endpoint} do
      GoogleApi.BigQuery.V2.Api.Jobs
      |> expect(:bigquery_jobs_query, 1, fn _conn, _proj_id, _opts ->
        {:error, :timeout}
      end)

      {:ok, cache_pid} = start_supervised({Logflare.Endpoints.Cache, {endpoint, %{}}})
      assert Process.alive?(cache_pid)

      assert {:error, %{"message" => :timeout}} = Endpoints.run_cached_query(endpoint)

      refute Process.alive?(cache_pid)
    end

    test "cache dies on timeout from query task", %{endpoint: endpoint} do
      test_response = [%{"testing" => "123"}]

      GoogleApi.BigQuery.V2.Api.Jobs
      |> expect(:bigquery_jobs_query, 1, fn _conn, _proj_id, _opts ->
        {:ok, TestUtils.gen_bq_response(test_response)}
      end)

      {:ok, cache_pid} = start_supervised({Logflare.Endpoints.Cache, {endpoint, %{}}})
      assert Process.alive?(cache_pid)

      # First query should succeed
      assert {:ok, %{rows: [%{"testing" => "123"}]}} = Endpoints.run_cached_query(endpoint)

      # Mock error response for refresh task
      GoogleApi.BigQuery.V2.Api.Jobs
      |> expect(:bigquery_jobs_query, 1, fn _conn, _proj_id, _opts ->
        {:error, :timeout}
      end)

      # should be larger than :proactive_requerying_seconds
      Process.sleep(1100)

      refute Process.alive?(cache_pid)
    end

    test "cache handles BigQuery error response bodies", %{endpoint: endpoint} do
      GoogleApi.BigQuery.V2.Api.Jobs
      |> expect(:bigquery_jobs_query, 1, fn _conn, _proj_id, _opts ->
        {:error, TestUtils.gen_bq_error("BQ Error")}
      end)

      {:ok, cache_pid} = start_supervised({Logflare.Endpoints.Cache, {endpoint, %{}}})
      assert Process.alive?(cache_pid)

      assert {:error, %{"message" => "BQ Error"}} = Endpoints.run_cached_query(endpoint)

      refute Process.alive?(cache_pid)
    end

    test "cache dies after cache_duration_seconds", %{endpoint: endpoint} do
      test_response = [%{"testing" => "123"}]

      GoogleApi.BigQuery.V2.Api.Jobs
      |> expect(:bigquery_jobs_query, 1, fn _conn, _proj_id, _opts ->
        {:ok, TestUtils.gen_bq_response(test_response)}
      end)

      {:ok, cache_pid} = start_supervised({Logflare.Endpoints.Cache, {endpoint, %{}}})
      assert Process.alive?(cache_pid)

      # First query should succeed
      assert {:ok, %{rows: [%{"testing" => "123"}]}} = Endpoints.run_cached_query(endpoint)

      # Cache should still be alive after 500ms
      Process.sleep(500)
      assert Process.alive?(cache_pid)

      # Cache should die after cache_duration_seconds (1 second)
      Process.sleep(600)
      refute Process.alive?(cache_pid)
    end

    test "cache updates cached results after proactive_requerying_seconds", %{endpoint: endpoint} do
      test_response = [%{"testing" => "123"}]

      GoogleApi.BigQuery.V2.Api.Jobs
      |> expect(:bigquery_jobs_query, 1, fn _conn, _proj_id, _opts ->
        {:ok, TestUtils.gen_bq_response(test_response)}
      end)

      {:ok, cache_pid} = start_supervised({Logflare.Endpoints.Cache, {endpoint, %{}}})
      assert Process.alive?(cache_pid)

      # First query should return first test response
      assert {:ok, %{rows: [%{"testing" => "123"}]}} = Endpoints.run_cached_query(endpoint)

      # Cache should still return first response before proactive_requerying_seconds
      Process.sleep(500)
      assert {:ok, %{rows: [%{"testing" => "123"}]}} = Endpoints.run_cached_query(endpoint)

      test_response = [%{"testing" => "456"}]

      GoogleApi.BigQuery.V2.Api.Jobs
      |> expect(:bigquery_jobs_query, 1, fn _conn, _proj_id, _opts ->
        {:ok, TestUtils.gen_bq_response(test_response)}
      end)

      # After proactive_requerying_seconds, should return updated response
      Process.sleep(600)
      assert {:ok, %{rows: [%{"testing" => "456"}]}} = Endpoints.run_cached_query(endpoint)
    end
  end
end
