defmodule LegacyFinance do
  @moduledoc """
  Library to calculate IRR through the Bisection method.
  """

  @type rate :: float
  @type date :: Date.t()

  defp xirr_reduction({period, value, rate}), do: value / :math.pow(1 + rate, period)

  @doc """
  Function to calculate the XIRR for a given array of dates and values.

  ## Examples
      iex> d = [{2015, 11, 1}, {2015,10,1}, {2015,6,1}]
      iex> v = [-800_000, -2_200_000, 1_000_000]
      iex> Finance.xirr(d,v)
      { :ok, 21.118359 }
  """
  @spec xirr([date], [number]) :: rate
  def xirr(dates, values) when length(dates) != length(values) do
    {:error, "Date and Value collections must have the same size"}
  end

  def xirr(dates, values) do
    # Filter out nil values early
    filtered_pairs =
      Enum.zip(dates, values) |> Enum.reject(fn {_date, value} -> is_nil(value) end)

    if length(filtered_pairs) == 0 do
      {:error, "No valid date-value pairs after filtering nil values"}
    else
      {dates, values} = Enum.unzip(filtered_pairs)

      dates =
        dates
        |> Enum.map(&Date.from_erl!/1)

      min_date = Enum.min(dates)
      {dates, values, dates_values} = compact_flow(Enum.zip(dates, values), min_date)

      cond do
        !verify_flow(values) ->
          {:error, "Values should have at least one positive or negative value."}

        length(dates) - length(values) == 0 && verify_flow(values) ->
          boundries = {guess_rate(dates, values), -1.0, +1.0}
          calculate(:xirr, dates_values, [], boundries, 0)

        true ->
          {:error, "Uncaught error"}
      end
    end
  end

  # def xirr

  defp compact_flow(dates_values, min_date) do
    flow = Enum.reduce(dates_values, %{}, &organize_value(&1, &2, min_date))
    {Map.keys(flow), Map.values(flow), Enum.filter(flow, &(elem(&1, 1) != 0))}
  end

  defp organize_value({date, value}, map, min_date) do
    # Guard against nil values
    if is_nil(value) do
      map
    else
      days = Date.diff(date, min_date) / 365.0
      Map.update(map, days, value, &(value + &1))
    end
  end

  defp verify_flow(values) do
    Enum.any?(values, fn x -> x > 0 end) && Enum.any?(values, fn x -> x < 0 end)
  end

  @spec guess_rate([date], [number]) :: rate
  defp guess_rate(dates, values) do
    {min_value, max_value} = Enum.min_max(values)
    period = 1 / (length(dates) - 1)

    # Guard against division by zero or nil values
    multiple =
      cond do
        # Default fallback
        min_value == 0 or min_value == nil -> 2.0
        # Default fallback
        max_value == nil -> 2.0
        true -> 1 + abs(max_value / min_value)
      end

    rate = :math.pow(multiple, period) - 1
    Float.round(rate, 3)
  end

  defp reached_boundry(rate, upper), do: abs(Float.round(rate - upper, 2)) == 0.0

  defp first_value_sign(dates_values) do
    [head | _] = dates_values
    {_, first_value} = head

    cond do
      first_value < 0 -> 1
      first_value > 0 -> -1
      true -> 0
    end
  end

  defp reduce_date_values(dates_values, rate) do
    list = dates_values

    acc =
      list
      |> Enum.map(fn x ->
        {
          elem(x, 0),
          elem(x, 1),
          rate
        }
      end)
      |> Enum.map(&xirr_reduction/1)
      |> Enum.sum()
      |> Float.round(4)

    acc * first_value_sign(dates_values)
  end

  defp calculate(:xirr, _date_values, +0.0, {rate, _bottom, _upper}, _tries) do
    {:ok, Float.round(rate, 6)}
  end

  defp calculate(:xirr, _date_values, _acc, {-1.0, _bottom, _upper}, _tries) do
    {:error, "Could not converge"}
  end

  defp calculate(:xirr, _date_values, _acc, {_, _, _}, 300) do
    {:error, "Unable to converge"}
  end

  defp calculate(:xirr, dates_values, _acc, {rate, bottom, upper}, tries) do
    acc = reduce_date_values(dates_values, rate)

    # Check for convergence with a small epsilon
    if abs(acc) < 1.0e-6 do
      {:ok, Float.round(rate, 6)}
    else
      resp =
        cond do
          acc < 0 ->
            # upper = rate
            # rate = (bottom + rate) / 2
            {(bottom + rate) / 2, bottom, rate}

          acc > 0 && reached_boundry(rate, upper) ->
            # bottom = rate
            # rate = (rate + upper) / 2
            # upper = upper + 1
            {(rate + upper) / 2, rate, upper + 1}

          acc > 0 && !reached_boundry(rate, upper) ->
            # bottom = rate
            # rate = (rate + upper) / 2
            {(rate + upper) / 2, rate, upper}

          acc == 0.0 ->
            # rate
            {rate, bottom, upper}
        end

      tries = tries + 1
      calculate(:xirr, dates_values, acc, resp, tries)
    end
  end
end

# defmodule Finance
