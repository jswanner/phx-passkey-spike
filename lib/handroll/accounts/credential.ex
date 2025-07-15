defmodule Handroll.Accounts.Credential do
  use Ecto.Schema
  @primary_key {:id, :binary, autogenerate: false}
  @foreign_key_type :binary_id
  schema "credentials" do
    field :description, :string
    field :public_key, Handroll.Types.Term

    timestamps(type: :utc_datetime_usec, updated_at: false)

    belongs_to :account, Handroll.Accounts.Account
  end
end
