defmodule LegacyFinance do
  @moduledoc """
  Library to calculate IRR through the Bisection method.
  """

  @type rate :: float
  @type date :: Date.t()

  @npv_relative_tolerance 1.0e-13
  @half_rate_unit 0.0000005

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
          bounds = {guess_rate(dates, values), -1.0, 1.0, false}
          calculate(dates_values, first_value_sign(dates_values), bounds, 0)

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
    base = 1.0 + rate

    Enum.reduce(dates_values, {0.0, 0.0}, fn {period, value}, {npv, scale} ->
      discounted = value / :math.pow(base, period)
      {npv + discounted, scale + abs(discounted)}
    end)
  end

  defp calculate(_, _, {rate, _, _, _}, _) when rate <= -1.0,
    do: {:error, "Could not converge"}

  defp calculate(_, _, _, 300), do: {:error, "Unable to converge"}

  defp calculate(dates_values, sign, {rate, bottom, upper, bracketed?}, tries) do
    {npv, scale} = reduce_date_values(dates_values, rate)

    candidate =
      if scale > 0.0 and abs(npv) <= @npv_relative_tolerance * scale do
        Float.round(rate, 6)
      end

    cond do
      candidate != nil and candidate <= -1.0 ->
        {:error, "Could not converge"}

      candidate != nil and verified_rounding?(dates_values, candidate) ->
        {:ok, candidate}

      npv == 0.0 ->
        {:error, "Could not converge"}

      true ->
        acc = npv * sign

        next =
          cond do
            acc < 0 ->
              {(bottom + rate) / 2, bottom, rate, true}

            # Once we have sampled the upper bound, keep narrowing the interval.
            not bracketed? and reached_boundry(rate, upper) ->
              {(rate + upper) / 2, rate, upper * 2.0, false}

            true ->
              {(rate + upper) / 2, rate, upper, bracketed?}
          end

        if next == {rate, bottom, upper, bracketed?} do
          rounded_rate = Float.round(rate, 6)

          if verified_rounding?(dates_values, rounded_rate) do
            {:ok, rounded_rate}
          else
            {:error, "Unable to converge"}
          end
        else
          calculate(dates_values, sign, next, tries + 1)
        end
    end
  end

  defp verified_rounding?(_, rate) when rate <= -1.0, do: false

  defp verified_rounding?(dates_values, rate) do
    {npv, scale} = reduce_date_values(dates_values, rate)

    if scale > 0.0 and abs(npv) <= @npv_relative_tolerance * scale do
      true
    else
      # A six-decimal result represents any root within half a unit of it.
      {left, _} = reduce_date_values(dates_values, rate - @half_rate_unit)
      {right, _} = reduce_date_values(dates_values, rate + @half_rate_unit)
      min(left, right) <= 0.0 and max(left, right) >= 0.0
    end
  end
end

# defmodule Finance
