use Bitwise

defmodule ElixirMatrixKeypad do
  @row_masks [0x7f, 0xbf, 0xdf, 0xef]
  def start_link do
    receive do
      {sender, device, i2c_address} ->
        {:ok, keypad} = I2c.start_link(device, i2c_address)
        initial_state = [<<0::size(4)>>, <<0::size(4)>>, <<0::size(4)>>, <<0::size(4)>>]
        loop_scan(keypad, sender, initial_state)
    end
  end

  defp loop_scan(keypad, sender, previous_state) do
    bitmap = scan_matrix(keypad)
    if(row_changed?(bitmap, previous_state), do: send(sender, bitmap))
    :timer.sleep 20
    loop_scan(keypad, sender, bitmap)
  end

  defp scan_matrix(keypad) do
    @row_masks |> Enum.map(fn (row_mask) -> scan_row(keypad, row_mask) end)
  end

  defp scan_row(keypad, row_mask) do
    <<_upper_row_mask::4, keys::4>> = I2c.write_read(keypad, <<row_mask>>, 1)
    presses = keys ^^^ 0xf
    <<presses::size(4)>>
  end

  defp row_changed?([], _), do: false
  defp row_changed?([<<row::size(4)>> | tail], [<<previous_row::size(4)>> | previous_tail]) do
    key_changed = row ^^^ previous_row !== 0
    case key_changed do
      true -> true
      false -> row_changed?(tail, previous_tail)
    end
  end
end

defmodule CharacterKeypad do
  def start_link do
    receive do
      { sender, keymap, i2c_device, i2c_address } ->
        pid = spawn(ElixirMatrixKeypad, :start_link, [])
        send pid, {self, i2c_device, i2c_address}
        monitor_matrix(sender, keymap)
    end
  end

  @initial_state [<<0::size(4)>>, <<0::size(4)>>, <<0::size(4)>>, <<0::size(4)>>]
  defp monitor_matrix(sender, keymap, previous_matrix \\ @initial_state) do
    receive do
      matrix ->
        keydowns = new_keydowns(matrix, previous_matrix, keymap)
        if(length(keydowns) > 0) do
          send sender, { :keydown, keydowns }
        end
        monitor_matrix(sender, keymap, matrix)
    end
  end

  defp new_keydowns(matrix, previous_matrix, keymap), do: _new_keydowns(matrix, previous_matrix, keymap, [])
  defp _new_keydowns([], _, _, keypresses), do: keypresses
  defp _new_keydowns([<<row::size(4)>> | tail], [<<previous_row::size(4)>> | previous_tail], [row_map | keymap_tail], keypresses) do
    keypresses = ((previous_row ^^^ row) &&& row) |> map_row_keys(row_map, keypresses)
    _new_keydowns(tail, previous_tail, keymap_tail, keypresses)
  end

  defp map_row_keys(_, [], keypresses), do: keypresses
  defp map_row_keys(row, [key | tail], keypresses) do
    char_pressed = (row &&& 0x08) !== 0
    keypresses = case char_pressed do
                    true -> [key | keypresses]
                    false -> keypresses
                  end
    map_row_keys(row <<< 1, tail, keypresses)
  end
end
