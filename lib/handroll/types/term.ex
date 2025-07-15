defmodule Handroll.Types.Term do
  use Ecto.Type

  def type, do: :binary

  def cast(term), do: {:ok, term}

  def dump(term) when is_binary(term), do: {:ok, term}
  def dump(term), do: {:ok, :erlang.term_to_binary(term)}

  def load(bin) when is_binary(bin), do: {:ok, :erlang.binary_to_term(bin)}
  def load(_bin), do: :error
end
