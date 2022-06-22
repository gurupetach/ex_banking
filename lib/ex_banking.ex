defmodule ExBanking do
  use Agent

  @default_amount 0.00

  def start_link() do
    Agent.start(fn -> %{} end, name: __MODULE__)
  end

  @spec create_user(user :: String.t()) :: :ok | {:error, :wrong_arguments | :user_already_exists}

  def create_user(user) when is_binary(user) do
    check_if_user_registered(user)
    |> case do
      {nil} ->
        Agent.update(
          __MODULE__,
          &Map.put(&1, user, %{
            active_transactions: 0,
            balance: @default_amount
          })
        )

      {:ok, _} ->
        {:error, :user_already_exists}
    end
  end

  def create_user(user) when not is_binary(user), do: {:error, :wrong_arguments}

  @spec deposit(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}

  def deposit(_user, _amount, currency) when not is_binary(currency),
    do: {:error, :wrong_arguments}

  def deposit(_user, amount, _currency) when not is_number(amount),
    do: {:error, :wrong_arguments}

  def deposit(user, amount, currency) when is_binary(user) and amount > 0 do
    check_if_user_registered(user)
    |> case do
      {:ok, _registered_user} ->
        Agent.update(__MODULE__, fn state ->
          state
          |> Map.update!(user, &add_balance(&1, amount))
        end)

        Agent.update(__MODULE__, fn state ->
          state
          |> Map.update!(user, &subtract_count(&1, amount))
        end)

        get_balance(user, currency)

      {nil} ->
        {:error, :user_does_not_exist}
    end
  end

  def deposit(_user, amount, _currency) when amount <= 0,
    do: {:error, :wrong_arguments}

  def deposit(user, _amount, _currency) when not is_binary(user),
    do: {:error, :wrong_arguments}

  def deposit(_user, amount, _currency) when not is_number(amount),
    do: {:error, :wrong_arguments}

  def deposit(_), do: {:error, :wrong_arguments}

  def add_balance(
        %{active_transactions: active_transactions, balance: balance} = user,
        amount
      ) do
    cond do
      # checks if number of ongoing transactions are less than ten before updating amount or else raises that arguments are many
      active_transactions <= 10 ->
        user
        |> Map.put(:active_transactions, active_transactions + 1)
        |> Map.put(:balance, balance + amount)

      true ->
        {:error, :too_many_arguments}
    end
  end

  def subtract_balance(
        %{active_transactions: active_transactions, balance: balance} = user,
        amount
      ) do
    cond do
      # checks if number of ongoing transactions are less than ten before updating amount or else raises that there are too many arguments
      active_transactions <= 10 ->
        user
        |> Map.put(:active_transactions, active_transactions + 1)
        |> Map.put(:balance, balance - amount)

      true ->
        {:error, :too_many_arguments}
    end
  end

  @spec withdraw(user :: String.t, amount :: number, currency :: String.t) :: {:ok, new_balance :: number} | {:error, :wrong_arguments | :user_does_not_exist | :not_enough_money | :too_many_requests_to_user}

  def withdraw(user, _amount, _currency) when not is_binary(user),
    do: {:error, :wrong_arguments}

  def withdraw(_user, amount, _currency) when not is_number(amount),
    do: {:error, :wrong_arguments}

  def withdraw(_user, _amount, currency) when not is_binary(currency),
    do: {:error, :wrong_arguments}

  def withdraw(user, amount, currency) when is_binary(user) and amount > 0 do
    with {:ok, _registered_user} <- check_if_user_registered(user),
         balance =
           Agent.get(__MODULE__, fn state ->
             state
             |> Map.get(user)
             |> Map.get(:balance)
           end),
         true <- balance >= amount do
      Agent.update(__MODULE__, fn state ->
        state
        |> Map.update!(user, &subtract_balance(&1, amount))
      end)

      Agent.update(__MODULE__, fn state ->
        state
        |> Map.update!(user, &subtract_count(&1, amount))
      end)

      get_balance(user, currency)
    else
      {nil} ->
        {:error, :user_does_not_exist}

      false ->
        {:error, :not_enough_money}
    end
  end

  def withdraw(_user, amount, _currency) when amount <= 0,
    do: {:error, :wrong_arguments}

  def withdraw(_user, _amount, currency) when not is_binary(currency),
    do: {:error, :wrong_arguments}

  def withdraw(_), do: {:error, :wrong_arguments}

  @spec get_balance(user :: String.t, currency :: String.t) :: {:ok, balance :: number} | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}

  def get_balance(user, _currency) when not is_binary(user), do: {:error, :wrong_arguments}
  def get_balance(_user, currency) when not is_binary(currency), do: {:error, :wrong_arguments}

  def get_balance(user, currency) when is_binary(user) and is_binary(currency) do
    with {:ok, registered_user} <-
           check_if_user_registered(user),
         active_transactions = registered_user |> Map.get(user) |> Map.get(:active_transactions),
         true <- active_transactions <= 10 do
      balance =
        registered_user
        |> Map.get(user)
        |> Map.get(:balance)
        |> to_string()
        |> String.to_float()
        |> Float.round(2)

      {:ok, balance}
    else
      {nil} ->
        {:error, :user_does_not_exist}

      false ->
        {:error, :too_many_arguments}
    end
  end

  @spec send(from_user :: String.t, to_user :: String.t, amount :: number, currency :: String.t) :: {:ok, from_user_balance :: number, to_user_balance :: number} | {:error, :wrong_arguments | :not_enough_money | :sender_does_not_exist | :receiver_does_not_exist | :too_many_requests_to_sender | :too_many_requests_to_receiver}

  def send(_from_user, _to_user, amount, _currency) when not is_number(amount),
    do: {:error, :wrong_arguments}

  def send(from_user, _to_user, _amount, _currency) when not is_binary(from_user),
    do: {:error, :wrong_arguments}

  def send(_from_user, to_user, _amount, _currency) when not is_binary(to_user),
    do: {:error, :wrong_arguments}

  def send(_from_user, _to_user, amount, _currency) when not is_number(amount),
    do: {:error, :wrong_arguments}

  def send(_from_user, _to_user, _amount, currency) when not is_binary(currency),
    do: {:error, :wrong_arguments}

  def send(from_user, to_user, amount, currency) when is_binary(from_user) and amount > 0 do
    with {:ok, _} <- check_if_user_registered(to_user),
         {:ok, from_user_balance} <- withdraw(from_user, amount, currency),
         {:ok, to_user_balance} <- deposit(to_user, amount, currency) do
      {:ok, from_user_balance, to_user_balance}
    else
      {nil} ->
        error = :receiver_does_not_exist
        {:error, error}

      {:error, :user_does_not_exist} ->
        error = :sender_does_not_exist
        {:error, error}

      {:error, :not_enough_money} ->
        {:error, :not_enough_money}
    end
  end

  def send(from_user, _to_user, _amount, _currency) when not is_binary(from_user),
    do: {:error, :wrong_arguments}

  def send(_from_user, to_user, _amount, _currency) when not is_binary(to_user),
    do: {:error, :wrong_arguments}

  def send(_from_user, _to_user, amount, _currency) when not is_number(amount),
    do: {:error, :wrong_arguments}

  def send(_from_user, _to_user, _amount, currency) when not is_binary(currency),
    do: {:error, :wrong_arguments}

  def send(_), do: {:error, :wrong_arguments}

  def check_if_user_registered(user) do
    user_map = Agent.get(__MODULE__, &Map.get(&1, user))

    user_map
    |> case do
      nil ->
        {nil}

      _ ->
        {:ok, %{user => user_map}}
    end
  end

  def subtract_count(
        %{active_transactions: active_transactions, balance: balance} = user,
        _amount
      ) do
    # subtracts active transactions after every successful transaction
    user
    |> Map.put(:active_transactions, active_transactions - 1)
    |> Map.put(:balance, balance)
  end

  def check_state(), do: Agent.get(__MODULE__, & &1)
end
