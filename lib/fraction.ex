defmodule Fraction do
  @moduledoc """
  Module to handle fractions
  """
  defstruct num: 0, den: 1

  def negative(%Fraction{} = fraction) do
    %Fraction{num: -fraction.num, den: fraction.den}
  end

  def to_float(%Fraction{} = fraction) do
    fraction.num / fraction.den
  end

  @typedoc """
   Rational numbers (num/den)
  """
  @type t :: %Fraction{
          num: integer,
          den: non_neg_integer
        }
end
