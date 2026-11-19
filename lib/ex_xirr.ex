defmodule ExXirr do
  @moduledoc """
  Library to calculate XIRR and absolute rate of return
  through the Newton Raphson method.
  """

  # Leave headroom for rounding the converged rate to six decimal places.
  @npv_relative_tolerance 1.0e-13
  @max_iterations 300
  @max_step_halvings 8
  @days_in_a_year 365

  # Public API

  @doc """
  Function to calculate the rate of return for a given array of
  dates and values.

  ## Examples

      iex> d = [{1985, 1, 1}, {1990, 1, 1}, {1995, 1, 1}]
      iex> v = [1000, -600, -200]
      iex> ExXirr.xirr(d,v)
      {:ok, -0.034592}
  """
  @spec xirr([Date.t()], [number]) :: float
  def xirr(dates, values) when length(dates) != length(values) do
    {:error, "Date and Value collections must have the same size"}
  end

  def xirr(dates, values) when length(dates) < 10 do
    LegacyFinance.xirr(dates, values)
  rescue
    e in _ ->
      error_message = Kernel.inspect(e)

      {:error, "#{inspect(error_message)}"}
  end

  def xirr(dates, values) do
    # Filter out nil values early
    filtered_pairs =
      Enum.zip(dates, values) |> Enum.reject(fn {_date, value} -> is_nil(value) end)

    if length(filtered_pairs) == 0 do
      {:error, "No valid date-value pairs after filtering nil values"}
    else
      {dates, values} = Enum.unzip(filtered_pairs)

      dates = Enum.map(dates, &Date.from_erl!(&1))
      min_date = dates |> List.first()
      {dates, values, dates_values} = compact_flow(Enum.zip(dates, values), min_date)

      cond do
        !verify_flow(values) ->
          {:error, "Values should have at least one positive or negative value."}

        length(dates) - length(values) == 0 && verify_flow(values) ->
          case calculate(dates_values, guess_rate(dates, values), 0) do
            {:ok, _} = result ->
              result

            {:error, _} = failure ->
              # A positive starting rate can overshoot a deeply negative root.
              case calculate(dates_values, -0.9, 0) do
                {:ok, _} = result -> result
                {:error, _} -> failure
              end
          end

        true ->
          {:error, "Uncaught error"}
      end
    end
  rescue
    e in _ ->
      error_message = Kernel.inspect(e)

      {:error, "#{inspect(error_message)}"}
  end

  @doc """
  Function to calculate the absolute rate of return for a given array
  of dates and values.

  ## Examples

      iex> d = [{1985, 1, 1}, {1990, 1, 1}, {1995, 1, 1}]
      iex> v = [1000, -600, -200]
      iex> {:ok, rate} = ExXirr.xirr(d,v)
      iex> ExXirr.absolute_rate(rate, 50)
      {:ok, -0.48}
  """
  @spec absolute_rate(float(), integer()) :: {:ok, float()} | {:error, String.t()}
  def absolute_rate(0, _), do: {:error, "Rate is 0"}

  def absolute_rate(rate, days) do
    try do
      if days < @days_in_a_year do
        {:ok, ((:math.pow(1 + rate, days / @days_in_a_year) - 1) * 100) |> Float.round(2)}
      else
        {:ok, (rate * 100) |> Float.round(2)}
      end
    rescue
      e in _ ->
        error_message = Kernel.inspect(e)

        {:error, "#{inspect(error_message)}"}
    end
  end

  # Private API

  @spec compact_flow(list(), Date.t()) :: tuple()
  defp compact_flow(dates_values, min_date) do
    flow = Enum.reduce(dates_values, %{}, &organize_value(&1, &2, min_date))
    {Map.keys(flow), Map.values(flow), Enum.filter(flow, &(elem(&1, 1) != 0))}
  end

  @spec organize_value(tuple(), map(), Date.t()) :: map()
  defp organize_value(date_value, dict, min_date) do
    {date, value} = date_value

    # Guard against nil values
    if is_nil(value) do
      dict
    else
      fraction = %Fraction{
        num: Date.diff(date, min_date),
        den: 365.0
      }

      Map.update(dict, fraction, value, &(value + &1))
    end
  end

  @spec verify_flow(list(float())) :: boolean()
  defp verify_flow(values) do
    {min, max} = Enum.min_max(values)
    min < 0 && max > 0
  end

  @spec guess_rate([Date.t()], [number]) :: float
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
    Float.round(rate, 6)
  end

  defp reduce_date_values(dates_values, base) do
    Enum.reduce(dates_values, {0.0, 0.0, 0.0}, fn {fraction, amount},
                                                  {npv, scaled_derivative, scale} ->
      period = Fraction.to_float(fraction)
      discounted = amount / :math.pow(base, period)

      {npv + discounted, scaled_derivative - period * discounted, scale + abs(discounted)}
    end)
  end

  defp calculate(dates_values, rate, tries) do
    case evaluate(dates_values, rate) do
      {:ok, npv, derivative, residual} ->
        calculate(dates_values, rate, npv, derivative, residual, tries)

      :error ->
        {:error, "Could not converge"}
    end
  end

  defp calculate(_, _, _, _, _, @max_iterations), do: {:error, "I give up"}

  defp calculate(dates_values, rate, npv, derivative, residual, tries) do
    cond do
      residual <= @npv_relative_tolerance ->
        rounded_rate = Float.round(rate, 6)

        # Rounding can turn a valid iterate into the singular rate -1.0.
        if rounded_rate > -1.0, do: {:ok, rounded_rate}, else: {:error, "Could not converge"}

      derivative == 0.0 ->
        {:error, "Could not converge"}

      true ->
        with {:ok, step} <- newton_step(rate, npv, derivative),
             {:ok, next_rate, next_npv, next_derivative, next_residual} <-
               improve(dates_values, rate, step, abs(npv), @max_step_halvings) do
          calculate(dates_values, next_rate, next_npv, next_derivative, next_residual, tries + 1)
        else
          :error -> {:error, "Could not converge"}
        end
    end
  end

  defp evaluate(dates_values, rate) when rate > -1.0 do
    {npv, derivative, scale} = reduce_date_values(dates_values, 1.0 + rate)
    if scale > 0.0, do: {:ok, npv, derivative, abs(npv) / scale}, else: :error
  rescue
    ArithmeticError -> :error
  end

  defp evaluate(_, _), do: :error

  # The NPV derivative is scaled_derivative / (1 + rate).
  defp newton_step(rate, npv, scaled_derivative) do
    {:ok, npv / scaled_derivative * (1.0 + rate)}
  rescue
    ArithmeticError -> :error
  end

  # Newton follows the raw NPV, not the normalized residual: its denominator
  # changes with the rate and can grow faster than the NPV moves toward zero.
  defp improve(dates_values, rate, step, abs_npv, halvings) do
    case evaluate_step(dates_values, rate, step) do
      {:ok, _, next_npv, _, _} = next when abs(next_npv) < abs_npv ->
        next

      _ when halvings > 0 ->
        improve(dates_values, rate, step / 2.0, abs_npv, halvings - 1)

      _ ->
        :error
    end
  end

  defp evaluate_step(dates_values, rate, step) do
    next_rate = rate - step

    with true <- next_rate != rate,
         {:ok, npv, derivative, residual} <- evaluate(dates_values, next_rate) do
      {:ok, next_rate, npv, derivative, residual}
    else
      _ -> :error
    end
  rescue
    ArithmeticError -> :error
  end
end
