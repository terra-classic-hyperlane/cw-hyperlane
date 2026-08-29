# Show a Warp Route in the Warp UI — fork & PR guide

How to make a deployed warp route appear in the Warp UI
(`hyperlane-warp-ui-template-igor`) by adding it, via fork + Pull Request, to the
registry the UI reads. Written for someone WITHOUT write access to the org repos;
the shortcut for maintainers is at the end.

## 1. Where the UI's token list comes from

The UI has **no tokens hardcoded**: `src/consts/warpRoutes.yaml` is empty and
`src/consts/warpRouteWhitelist.ts` is `null`, which means *"show every route
found in the configured registry"*. The registry is set in the UI's `.env`:

```bash
NEXT_PUBLIC_REGISTRY_URL=https://github.com/terra-classic-hyperlane/hyperlane-registry
NEXT_PUBLIC_REGISTRY_BRANCH=terra-classic-warp
```

The UI fetches that branch **at runtime** (GithubRegistry via
`proxy.hyperlane.xyz`). So a route shows up in the UI as soon as its file is
**merged into the `terra-classic-warp` branch** of
`terra-classic-hyperlane/hyperlane-registry` — no UI rebuild or redeploy needed
(allow a few minutes of proxy cache).

> This is a different repo/branch from the official `hyperlane-xyz/hyperlane-registry`
> (where columbus-5/rebel-2 are canonical since PR #1559). Production tokens should
> eventually be PRed there too, but the **UI** only reads the fork's
> `terra-classic-warp` branch.

## 2. What you add: one config file per token

> 💡 **You don't have to write this file by hand**: `create-warp-evm.sh`
> generates it at the end of every run (STEP 9) as
> `warp/registry-<token>-config.yaml` — TC collateral plus every mainnet
> synthetic already deployed (EVM + Solana). Review it, copy it to the registry
> path below, and open the PR.

One folder per symbol under `deployments/warp_routes/`, one YAML listing every
chain the token lives on. Follow the naming of the existing IGORFAKE file:

```
deployments/warp_routes/<SYMBOL>/terraclassic-<evm/solana chains>-config.yaml
```

Real example — FAKEFAKE (TC collateral + BSC synthetic), file
`deployments/warp_routes/FAKEFAKE/terraclassic-bsc-config.yaml`:

```yaml
# yaml-language-server: $schema=../schema.json
tokens:
  - addressOrDenom: terra1zkkk9km8f6gf5vgn4zf66ep0djztqqkvns8jws8c9f85v4tfxrvq9n2wlk
    chainName: terraclassic
    collateralAddressOrDenom: terra1f45rp85m53688ykan8mgjmfyz43d5h7psgawz5n775wde6vrzj5s4tvpwq
    connections:
      - token: ethereum|bsc|0x07289a10E1c4E8218AE2ACC599FfC29C68f32C47
    decimals: 6
    name: FAKEFAKE
    standard: CwHypCollateral
    symbol: FAKEFAKE
  - addressOrDenom: "0x07289a10E1c4E8218AE2ACC599FfC29C68f32C47"
    chainName: bsc
    connections:
      - token: cosmos|terraclassic|terra1zkkk9km8f6gf5vgn4zf66ep0djztqqkvns8jws8c9f85v4tfxrvq9n2wlk
    decimals: 6
    name: FAKEFAKE
    standard: EvmHypSynthetic
    symbol: FAKEFAKE
options:
  # Interchain fee is quoted DYNAMICALLY from the TC IGP by the UI — do NOT add
  # interchainFeeConstants. localFeeConstants = fixed local fee on the TC origin.
  localFeeConstants:
    - origin: terraclassic
      destination: bsc
      amount: 283215
      addressOrDenom: uluna
```

Rules the file must follow (see the IGORFAKE file in the same folder as the
canonical reference):

- **`addressOrDenom`** = the *warp* contract (TC: `terra1…` warp, EVM: HypERC20
  proxy, Solana: token program id). **`collateralAddressOrDenom`** = the cw20 /
  SPL mint being wrapped (collateral sides only).
- **`connections`** must exist in BOTH directions, format
  `<protocol>|<chainName>|<address>` with protocol `cosmos` / `ethereum` /
  `sealevel`.
- **`standard`**: `CwHypCollateral` (TC), `EvmHypSynthetic` (BSC/ETH),
  `SealevelHypSynthetic` (Solana).
- Every address copied from `warp-evm-config.json` / verified on-chain — never
  typed by hand. The route must already be fully wired
  (hook + enroll + `set_route`, [WARP-EVM.md](WARP-EVM.md) §5.4–5.7) and tested
  in both directions BEFORE the PR.
- If the token's chain is new to the registry, its `chains/<chain>/metadata.yaml`
  must exist on the branch too (terraclassic/bsc/ethereum/solanamainnet already do).

## 2.1 Test the route in the live UI BEFORE the PR (copy & paste)

You can validate the YAML and the route end-to-end in the production UI at
**<https://terraclassic-bridge.xyz/>** without touching the registry:

1. Open the bridge and click the **“+”** button (right-hand side) — the
   **“Add Warp Route Configs”** dialog opens;
2. Paste the FULL content of the generated
   `warp/registry-<token>-config.yaml` into the text box;
3. Click **“Add Config”** — the route appears listed at the bottom of the
   dialog (e.g. `FAKEFAKE/bsc`) and the token becomes selectable in the form;
4. Run a real transfer in BOTH directions to confirm the route works.

⚠️ Routes added this way live **only in your own browser** (localStorage) —
nobody else sees them. That's exactly what makes it a safe pre-PR test: once
the transfers work, open the PR (below) so the route appears for everyone.

## 3. Fork & PR, step by step

```bash
# 1. Fork terra-classic-hyperlane/hyperlane-registry on GitHub (button "Fork"),
#    then clone YOUR fork:
git clone git@github.com:<your-user>/hyperlane-registry.git
cd hyperlane-registry

# 2. Branch FROM terra-classic-warp (NOT from main):
git remote add upstream https://github.com/terra-classic-hyperlane/hyperlane-registry.git
git fetch upstream terra-classic-warp
git checkout -b add-fakefake-route upstream/terra-classic-warp

# 3. Add the file:
mkdir -p deployments/warp_routes/FAKEFAKE
$EDITOR deployments/warp_routes/FAKEFAKE/terraclassic-bsc-config.yaml

# 4. Commit and push to your fork:
git add deployments/warp_routes/FAKEFAKE
git commit -m "feat(warp): add FAKEFAKE terraclassic-bsc route"
git push -u origin add-fakefake-route

# 5. Open the PR — base repo terra-classic-hyperlane/hyperlane-registry,
#    base branch terra-classic-warp (NOT main):
gh pr create \
  --repo terra-classic-hyperlane/hyperlane-registry \
  --base terra-classic-warp \
  --head <your-user>:add-fakefake-route \
  --title "feat(warp): add FAKEFAKE terraclassic-bsc route" \
  --body "Adds the FAKEFAKE warp route (TC collateral + BSC synthetic). All addresses verified on-chain."
```

Common mistakes the review will bounce:

- PR opened against `main`, or against the upstream `hyperlane-xyz` repo (the UI
  reads neither — only the fork's `terra-classic-warp`).
- Route not yet enrolled/tested (`transfer_remote` fails with "route not found").
- Missing reverse `connections`, wrong `standard`, or addresses not matching the
  chain (checksum/bech32).
- `interchainFeeConstants` added back — the UI quotes the IGP dynamically.

**Maintainers** (write access to the org repo): skip the fork — branch off
`terra-classic-warp` in the repo itself, push, and open an internal PR with the
same base branch.

## 4. After the merge

Nothing to deploy: the UI loads the registry from GitHub at page load. If the
token doesn't appear after a few minutes, hard-refresh (the
`proxy.hyperlane.xyz` cache and the browser cache are the usual suspects) and
check the browser console for schema errors in the new YAML.
