use Bitwise

defmodule ElixirMatrixKeypad do
  def start_link do
    receive do
      {sender, device, i2c_address} ->
        {:ok, keypad} = I2c.start_link(device, i2c_address)
        scan(keypad, sender)
    end
  end

  defp scan(keypad, sender) do
    scan(keypad, sender, [<<0::size(4)>>,<<0::size(4)>>,<<0::size(4)>>,<<0::size(4)>>])
  end

  defp scan(keypad, sender, previous_state) do
    bitmap = scan_matrix(keypad)
    cond do
      row_changed?(bitmap, previous_state) -> send(sender, bitmap)
      true -> nil
    end
    :timer.sleep 20
    scan(keypad, sender, bitmap)
  end

  defp scan_matrix(keypad) do
    row_masks = [0x7f, 0xbf, 0xdf, 0xef]
    Enum.map(row_masks, fn (row_mask) ->
      scan_row(keypad, row_mask)
    end)
  end

  defp scan_row(keypad, row_mask) do
    <<_upper_row_mask::4, keys::4>> = I2c.write_read(keypad, <<row_mask>>, 1)
    presses = keys ^^^ 0xf
    <<presses::size(4)>>
  end

  defp row_changed?([], []), do: false
  defp row_changed?([row | tail], [previous_row | previous_tail]) do
    cond do
      key_changed?(row, previous_row) -> true
      true -> row_changed?(tail, previous_tail)
    end
  end

  defp key_changed?(<<row::4>>, <<previous_row::4>>) do
    row ^^^ previous_row !== 0
  end
end

defmodule KeypadScanner do
  def start do
    pid = spawn(ElixirKeypad, :start_link, [])
    send pid, {self, "i2c-1", 0x20}
    keep_scanning
  end

  defp keep_scanning do
    receive do
      matrix -> print_matrix(matrix)
    end
    keep_scanning
  end

  defp print_matrix([]), do: nil
  defp print_matrix([row | tail]) do
    <<bits::4>> = row
    :io.format("~4.2.0B~n", [bits])
    print_matrix(tail)
  end
end
