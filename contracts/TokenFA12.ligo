type account is record [
  balance: nat;
  allowances: map (address, nat);
]

type storage is record [
  totalSupply: nat;
  ledger : big_map (address, account);
]

type default_type is unit
type mint_type is unit
type redeem_type is michelson_pair(nat, "value", contract(nat), "")
type transfer_type is michelson_pair(address, "from", michelson_pair(address, "to", nat, "value"), "")
type approve_type is michelson_pair(address, "spender", nat, "value")
type balance_type is michelson_pair(address, "owner", contract(nat), "")
type allowance_type is michelson_pair(michelson_pair(address, "owner", address, "spender"), "", contract(nat), "")
type total_supply_type is michelson_pair(unit, "", contract(nat), "")

type action is 
| Default of default_type
| Mint of mint_type
| Redeem of redeem_type
| Transfer of transfer_type
| Approve of approve_type
| GetBalance of balance_type
| GetAllowance of allowance_type
| GetTotalSupply of total_supply_type

function getAccount(const owner: address; const s: storage) : account is 
case s.ledger[owner] of None -> record [
  balance = 0n;
  allowances = (map [] : map(address, nat));
]
| Some(acc) -> acc
end

function mint(const s: storage) : storage is 
block {
  const src: account = getAccount(Tezos.sender, s);

  if Tezos.amount = 0tz then failwith("InsufficientFund") else skip;

  src.balance := src.balance + (Tezos.amount / 1mutez);
  s.ledger[Tezos.sender] := src;
} with s

function redeem(const value: nat; const s: storage) : (list(operation) * storage) is 
block {
  const dst: account = getAccount(Tezos.sender, s);

  if dst.balance < value then failwith("InsufficientBalance") else skip;

  const receiver : contract (unit) =
  case (Tezos.get_contract_opt (Tezos.sender): option(contract(unit))) of
    Some (contract) -> contract
  | None -> (failwith ("InvalidContract") : (contract(unit)))
  end;

  const redeemOperation : operation = Tezos.transaction(unit, value * 1mutez, receiver);
  const operations : list (operation) = list [redeemOperation];

  dst.balance := abs(dst.balance - value);
  s.ledger[Tezos.sender] := dst;
} with (operations, s)

function transfer(const owner: address; const receiver: address; const value: nat; const s: storage) : storage is 
block {
  const src: account = getAccount(owner, s);
  const dst: account = getAccount(receiver, s);
  
  // check approve
  if Tezos.sender = owner then skip else block {
    const allowance: nat = case src.allowances[Tezos.sender] of
    | None -> 0n
    | Some(v) -> v
    end;
    if allowance < value then failwith("NotPermitted") else
    src.allowances[Tezos.sender] := abs(allowance - value);
  };

  if src.balance < value then failwith("LowBalance") else skip;
  src.balance := abs(src.balance - value);
  dst.balance := src.balance + value;

  s.ledger[owner] := src;
  s.ledger[receiver] := dst;
} with s

function approve(const spender: address; const value: nat; const s: storage) : storage is 
block {
  const acc: account = getAccount(Tezos.sender, s);
  acc.allowances[spender] := value;
  s.ledger[Tezos.sender] := acc;
} with s

function getAllowance(const owner: address; const spender: address; const receiver: contract(nat); const s: storage): list(operation) is 
block {
  const acc: account = getAccount(owner, s);
  const allowance: nat = case acc.allowances[spender] of
  | None -> 0n
  | Some(v) -> v
  end
} with list [Tezos.transaction(allowance, 0mutez, receiver)]

function getBalance(const owner: address; const receiver: contract(nat); const s: storage): list(operation) is 
block {
  const acc: account = getAccount(owner, s);
} with list [Tezos.transaction(acc.balance, 0mutez, receiver)]

function getTotalSupply(const receiver: contract(nat); const s: storage): list(operation) is 
list [Tezos.transaction(s.totalSupply, 0mutez, receiver)]

function main (const a: action; var s: storage) : (list(operation) * storage) is
case a of 
| Default -> ((nil: list(operation)), mint(s))
| Mint -> ((nil: list(operation)), mint(s))
| Redeem(v) -> redeem(v.0, s)
| Transfer(v) -> ((nil: list(operation)), transfer(v.0, v.1.0, v.1.1, s))
| Approve(v) -> ((nil: list(operation)), approve(v.0, v.1, s))
| GetBalance(v) -> (getBalance(v.0, v.1, s), s)
| GetAllowance(v) -> (getAllowance(v.0.0, v.0.1, v.1, s), s)
| GetTotalSupply(v) -> (getTotalSupply(v.1, s), s)
end