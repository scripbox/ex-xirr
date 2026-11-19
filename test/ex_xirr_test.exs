defmodule ExXirrTest do
  use ExUnit.Case, async: true
  doctest ExXirr

  describe "xirr/2" do
    test "positive and negative flow in the same day" do
      d = [{2014, 04, 15}, {2014, 04, 15}, {2014, 10, 19}]
      v = [-10000.0, 10000.0, 500.0]

      assert ExXirr.xirr(d, v) ==
               {:error, "Values should have at least one positive or negative value."}
    end

    test "impossible returns on investments" do
      d = [{2015, 11, 1}, {2015, 10, 1}, {2015, 6, 1}]
      v = [-800_000, -2_200_000, 1_000_000]
      assert ExXirr.xirr(d, v) == {:ok, 21.118359}
    end

    test "bad investment" do
      d = [{1985, 1, 1}, {1990, 1, 1}, {1995, 1, 1}]
      v = [1000, -600, -200]
      assert ExXirr.xirr(d, v) == {:ok, -0.034592}
    end

    test "repeated cashflow" do
      v = [1000.0, 2000.0, -2000.0, -4000.0]
      d = [{2011, 12, 07}, {2011, 12, 07}, {2013, 05, 21}, {2013, 05, 21}]

      assert ExXirr.xirr(d, v) == {:ok, 0.610359}
    end

    test "ok investment" do
      v = [1000.0, -600.0, -6000.0]
      d = [{1985, 1, 1}, {1990, 1, 1}, {1995, 1, 1}]

      assert ExXirr.xirr(d, v) == {:ok, 0.225683}
    end

    test "Newton returns a convergence error for a runaway rate" do
      v = [
        105_187.06,
        816_709.66,
        479_069.684,
        937_309.708,
        88622.661,
        100_000.0,
        80000.0,
        403_627.95,
        508_117.9,
        789_706.87,
        -88622.661,
        -789_706.871,
        -688_117.9,
        -403_627.95,
        403_627.95,
        789_706.871,
        88622.661,
        688_117.9,
        45129.14,
        26472.08,
        51793.2,
        126_605.59,
        278_532.29,
        99284.1,
        58238.57,
        113_945.03,
        405_137.88,
        -405_137.88,
        165_738.23,
        -165_738.23,
        144_413.24,
        84710.65,
        -84710.65,
        -144_413.24
      ]

      d = [
        {2011, 12, 07},
        {2011, 12, 07},
        {2011, 12, 07},
        {2012, 01, 18},
        {2012, 07, 03},
        {2012, 07, 03},
        {2012, 07, 19},
        {2012, 07, 23},
        {2012, 07, 23},
        {2012, 07, 23},
        {2012, 09, 11},
        {2012, 09, 11},
        {2012, 09, 11},
        {2012, 09, 11},
        {2012, 09, 12},
        {2012, 09, 12},
        {2012, 09, 12},
        {2012, 09, 12},
        {2013, 03, 11},
        {2013, 03, 11},
        {2013, 03, 11},
        {2013, 03, 11},
        {2013, 03, 28},
        {2013, 03, 28},
        {2013, 03, 28},
        {2013, 03, 28},
        {2013, 05, 21},
        {2013, 05, 21},
        {2013, 05, 21},
        {2013, 05, 21},
        {2013, 05, 21},
        {2013, 05, 21},
        {2013, 05, 21},
        {2013, 05, 21}
      ]

      assert ExXirr.xirr(d, v) == {:error, "Could not converge"}
    end

    test "Newton converges after shortening steps below -100%" do
      dates = for day <- 0..8, do: Date.add(~D[2010-01-01], 170 * day) |> Date.to_erl()
      amounts = [50_000, 18_000, 57_000, 33_000, 22_000, -20_000, -35_000, -28_000, -18_000]
      [first_date | rest] = dates

      assert ExXirr.xirr(dates, amounts) == {:ok, -0.235883}

      assert ExXirr.xirr(dates ++ [{2026, 1, 1}], amounts ++ [0]) ==
               {:ok, -0.235883}

      assert ExXirr.xirr([first_date, {2010, 1, 2} | rest], [25_000, 25_000 | tl(amounts)]) ==
               {:ok, -0.235912}
    end

    test "Newton measures step progress using NPV rather than the scaled residual" do
      dates = for year <- 0..9, do: Date.add(~D[2010-01-01], 365 * year) |> Date.to_erl()

      # NPV in q = 1 / (1 + rate) is (q - 0.1) * (q - 2.5).
      amounts = [0.25, -2.6, 1 | List.duplicate(0, 7)]
      assert ExXirr.xirr(dates, amounts) == {:ok, 9.0}
    end

    test "Newton refines the rate before rounding near a six-decimal boundary" do
      dates =
        for day <- [0 | Enum.to_list(30..38)], do: Date.add(~D[2010-01-01], day) |> Date.to_erl()

      amount = 1_000 * :math.pow(1 + 0.069000501, 30 / 365)
      amounts = [-1_000, amount | List.duplicate(0, 8)]

      assert ExXirr.xirr(dates, amounts) == {:ok, 0.069001}
    end

    test "Newton converges with a negative derivative" do
      dates = for year <- 0..9, do: Date.add(~D[2010-01-01], 365 * year) |> Date.to_erl()

      # The cash flow doubles in nine years, so 1 + rate = 2^(1/9).
      for amount <- [0.001, 1_000, 1_000_000_000] do
        amounts = [-amount | List.duplicate(0, 8)] ++ [2 * amount]
        assert ExXirr.xirr(dates, amounts) == {:ok, 0.08006}
      end
    end

    test "bisection returns the same rate across cash-flow scales" do
      dates = [{2010, 1, 1}, {2010, 2, 19}]
      closing = 50 * :math.pow(1 - 0.09012991845, 49 / 365)

      for scale <- [1.0e-8, 1.0, 1.0e8] do
        assert ExXirr.xirr(dates, [50 * scale, -closing * scale]) == {:ok, -0.09013}
      end
    end

    test "bisection does not accept small cash flows with no root" do
      dates = for year <- 0..2, do: Date.add(~D[2010-01-01], 365 * year) |> Date.to_erl()

      # In q = 1 / (1 + rate), the NPV is 1.0e-6 * ((q - 1)^2 + 0.01).
      assert {:error, _} = ExXirr.xirr(dates, [1.01e-6, -2.0e-6, 1.0e-6])
    end

    test "bisection never returns a rate that rounds to -100%" do
      dates = [{2010, 1, 1}, {2011, 1, 1}]

      assert ExXirr.xirr(dates, [1_000, -0.001]) == {:ok, -0.999999}
      assert {:error, _} = ExXirr.xirr(dates, [1_000, -0.0001])
    end

    test "Newton retries from a negative guess after overshooting" do
      dates = for year <- 0..9, do: Date.add(~D[2010-01-01], 365 * year) |> Date.to_erl()
      amounts = [1_000 | List.duplicate(0, 8)] ++ [-1_000 * :math.pow(0.2, 9)]

      assert ExXirr.xirr(dates, amounts) == {:ok, -0.8}
    end

    test "wrong size" do
      d = [
        {2014, 04, 15},
        {2014, 10, 19}
      ]

      v = [
        -10000.0,
        305.6,
        500.0
      ]

      assert ExXirr.xirr(d, v) == {:error, "Date and Value collections must have the same size"}
    end

    test "wrong values" do
      d = [
        {2014, 04, 15},
        {2014, 10, 19}
      ]

      v = [
        305.6,
        500.0
      ]

      assert ExXirr.xirr(d, v) ==
               {:error, "Values should have at least one positive or negative value."}
    end

    test "not a bad investment" do
      d = [{2008, 2, 5}, {2008, 7, 5}, {2009, 1, 5}]
      v = [2750.0, -1000.0, -2000.0]

      assert ExXirr.xirr(d, v) == {:ok, 0.123631}
    end

    test "bisection expands the search for a high annualized rate" do
      d = [{2017, 1, 1}, {2017, 1, 5}]
      v = [10000, -11000]
      assert ExXirr.xirr(d, v) == {:ok, 5984.253106}
    end

    test "check for arithmetic error for negative closing value" do
      d = [{1995, 10, 16}, {2003, 11, 14}, {2016, 11, 2}, {2022, 12, 26}]
      v = [1000, 0.0, -13511.34, 17034.345]

      assert ExXirr.xirr(d, v) ==
               {:error,
                "\"%ArithmeticError{message: \\\"bad argument in arithmetic expression\\\"}\""}
    end
  end
end
