RSpec.shared_examples 'rejects malformed position snapshots' do |order_method|
  {
    'a non-object row' => [nil, 'expected an object'],
    'a missing side' => [{ 'side' => nil }, 'side'],
    'an unknown side' => [{ 'side' => 'UNKNOWN' }, 'side'],
    'a size with trailing junk' => [{ 'size' => '0.1 BTC' }, 'size'],
    'a price with trailing junk' => [{ 'price' => '1000000 JPY' }, 'price'],
    'a non-finite size' => [{ 'size' => 'Infinity' }, 'size'],
    'a non-finite price' => [{ 'price' => 'NaN' }, 'price'],
    'a zero size' => [{ 'size' => 0 }, 'size'],
    'a negative price' => [{ 'price' => -1 }, 'price']
  }.each do |description, (overrides, error)|
    context "with #{description}" do
      let(:positions) do
        valid = position(side: 'BUY', price: '1e6', size: '0.1')
        [valid, overrides && valid.merge(overrides).compact]
      end

      it 'reports the invalid row and submits no order' do
        expect { run_command }.to output(/Failed to look up positions: row 2: #{error}/).to_stderr
        expect(private_client).not_to have_received(order_method)
      end
    end
  end
end
