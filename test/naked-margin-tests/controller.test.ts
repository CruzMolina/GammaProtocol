import {
  CallTesterInstance,
  MarginCalculatorInstance,
  MockOtokenInstance,
  MockERC20Instance,
  MockOracleInstance,
  MockWhitelistModuleInstance,
  MarginPoolInstance,
  ControllerInstance,
  AddressBookInstance,
  OwnedUpgradeabilityProxyInstance,
} from '../../build/types/truffle-types'
import BigNumber from 'bignumber.js'
import {createTokenAmount, createScaledNumber} from '../utils'

const {expectRevert, expectEvent, time} = require('@openzeppelin/test-helpers')

const CallTester = artifacts.require('CallTester.sol')
const MockERC20 = artifacts.require('MockERC20.sol')
const MockOtoken = artifacts.require('MockOtoken.sol')
const MockOracle = artifacts.require('MockOracle.sol')
const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy.sol')
const MarginCalculator = artifacts.require('MarginCalculator.sol')
const MockWhitelistModule = artifacts.require('MockWhitelistModule.sol')
const AddressBook = artifacts.require('AddressBook.sol')
const MarginPool = artifacts.require('MarginPool.sol')
const Controller = artifacts.require('Controller.sol')
const MarginVault = artifacts.require('MarginVault.sol')

// address(0)
const ZERO_ADDR = '0x0000000000000000000000000000000000000000'

enum ActionType {
  OpenVault,
  MintShortOption,
  BurnShortOption,
  DepositLongOption,
  WithdrawLongOption,
  DepositCollateral,
  WithdrawCollateral,
  SettleVault,
  Redeem,
  Call,
  InvalidAction,
  Liquidate,
}

contract(
  'Controller',
  ([owner, accountOwner1, accountOwner2, accountOperator1, holder1, fullPauser, partialPauser, random]) => {
    // ERC20 mock
    let usdc: MockERC20Instance
    let weth: MockERC20Instance
    let weth2: MockERC20Instance
    // Oracle module
    let oracle: MockOracleInstance
    // calculator module
    let calculator: MarginCalculatorInstance
    // margin pool module
    let marginPool: MarginPoolInstance
    // whitelist module mock
    let whitelist: MockWhitelistModuleInstance
    // addressbook module mock
    let addressBook: AddressBookInstance
    // controller module
    let controllerImplementation: ControllerInstance
    let controllerProxy: ControllerInstance

    const usdcDecimals = 6
    const wethDecimals = 18
    let vaultCounter = 1

    before('Deployment', async () => {
      // addressbook deployment
      addressBook = await AddressBook.new()
      // ERC20 deployment
      usdc = await MockERC20.new('USDC', 'USDC', usdcDecimals)
      weth = await MockERC20.new('WETH', 'WETH', wethDecimals)
      weth2 = await MockERC20.new('WETH', 'WETH', wethDecimals)
      // deploy Oracle module
      oracle = await MockOracle.new(addressBook.address, {from: owner})
      // calculator deployment
      calculator = await MarginCalculator.new(oracle.address)
      // margin pool deployment
      marginPool = await MarginPool.new(addressBook.address)
      // whitelist module
      whitelist = await MockWhitelistModule.new()
      // set margin pool in addressbook
      await addressBook.setMarginPool(marginPool.address)
      // set calculator in addressbook
      await addressBook.setMarginCalculator(calculator.address)
      // set oracle in AddressBook
      await addressBook.setOracle(oracle.address)
      // set whitelist module address
      await addressBook.setWhitelist(whitelist.address)
      // deploy Controller module
      const lib = await MarginVault.new()
      await Controller.link('MarginVault', lib.address)
      controllerImplementation = await Controller.new()

      // set controller address in AddressBook
      await addressBook.setController(controllerImplementation.address, {from: owner})

      // check controller deployment
      const controllerProxyAddress = await addressBook.getController()
      controllerProxy = await Controller.at(controllerProxyAddress)
      const proxy: OwnedUpgradeabilityProxyInstance = await OwnedUpgradeabilityProxy.at(controllerProxyAddress)

      assert.equal(await proxy.proxyOwner(), addressBook.address, 'Proxy owner address mismatch')
      assert.equal(await controllerProxy.owner(), owner, 'Controller owner address mismatch')
      assert.equal(await controllerProxy.systemPartiallyPaused(), false, 'system is partially paused')

      // make everyone rich
      await usdc.mint(accountOwner1, createTokenAmount(10000, usdcDecimals))
      await usdc.mint(accountOperator1, createTokenAmount(10000, usdcDecimals))
      await usdc.mint(random, createTokenAmount(10000, usdcDecimals))
    })

    describe('Open naked margin vault', () => {
      it('should open a naked margin vault', async () => {
        const actionArgs = [
          {
            actionType: ActionType.OpenVault,
            owner: accountOwner1,
            secondAddress: ZERO_ADDR,
            asset: ZERO_ADDR,
            vaultId: vaultCounter.toString(),
            amount: '0',
            // naked margin
            index: '1',
            data: ZERO_ADDR,
          },
        ]
        await controllerProxy.operate(actionArgs, {from: accountOwner1})
        assert.equal((await controllerProxy.getProceed(accountOwner1, '1')).toString(), '0')
      })
    })

    describe('deposit collateral', () => {
      it('should not deposit unwhitelisted collateral', async () => {
        const collateralToDeposit = createTokenAmount(100, usdcDecimals)
        const actionArgs = [
          {
            actionType: ActionType.DepositCollateral,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: usdc.address,
            vaultId: vaultCounter.toString(),
            amount: collateralToDeposit,
            index: '0',
            data: ZERO_ADDR,
          },
        ]
        await usdc.approve(marginPool.address, collateralToDeposit, {from: accountOperator1})
        await expectRevert(
          controllerProxy.operate(actionArgs, {from: accountOwner1}),
          'Controller: asset is not whitelisted to be used as collateral',
        )
      })

      it('should revert if collateral is not above the DUST limit', async () => {
        const collateralToDeposit = createTokenAmount(1, usdcDecimals)
        const actionArgs = [
          {
            actionType: ActionType.DepositCollateral,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: usdc.address,
            vaultId: vaultCounter.toString(),
            amount: collateralToDeposit,
            index: '0',
            data: ZERO_ADDR,
          },
        ]

        await whitelist.whitelistCollateral(usdc.address)
        await oracle.setDustLimit(usdc.address, createTokenAmount(100, usdcDecimals))
        await usdc.approve(marginPool.address, collateralToDeposit, {from: accountOwner1})
        await expectRevert(
          controllerProxy.operate(actionArgs, {from: accountOwner1}),
          'Controller: naked margin vault must have at least the dust limit of collateral',
        )
      })

      it('should not be allowed to use long as collateral', async () => {
        const expiryTime = new BigNumber(60 * 60 * 24) // after 1 day
        const longOtoken = await MockOtoken.new()
        // init otoken
        await longOtoken.init(
          addressBook.address,
          weth.address,
          usdc.address,
          usdc.address,
          createTokenAmount(200),
          new BigNumber(await time.latest()).plus(expiryTime),
          true,
        )

        const longToDeposit = createTokenAmount(1)
        await longOtoken.mintOtoken(accountOwner1, longToDeposit)

        // whitelist long otoken
        await whitelist.whitelistOtoken(longOtoken.address)
        const actionArgs = [
          {
            actionType: ActionType.DepositLongOption,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: longOtoken.address,
            vaultId: vaultCounter.toString(),
            amount: longToDeposit,
            index: '0',
            data: ZERO_ADDR,
          },
        ]
        await longOtoken.approve(marginPool.address, longToDeposit, {from: accountOwner1})
        await expectRevert(
          controllerProxy.operate(actionArgs, {from: accountOwner1}),
          'Controller: Long otokens not allowed in this vault',
        )
      })

      it('should allow deposit of white-listed collateral above the DUST limit', async () => {
        const collateralToDeposit = createTokenAmount(2, usdcDecimals)
        const actionArgs = [
          {
            actionType: ActionType.DepositCollateral,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: usdc.address,
            vaultId: vaultCounter.toString(),
            amount: collateralToDeposit,
            index: '0',
            data: ZERO_ADDR,
          },
        ]

        await oracle.setDustLimit(usdc.address, createTokenAmount(1, usdcDecimals))
        await usdc.approve(marginPool.address, collateralToDeposit, {from: accountOwner1})
        await controllerProxy.operate(actionArgs, {from: accountOwner1})
        const vault = await controllerProxy.getVault(accountOwner1, vaultCounter.toString())
        assert.equal(vault.collateralAssets[0].toString(), usdc.address)
        assert.equal(vault.collateralAmounts[0].toString(), collateralToDeposit.toString())
      })
    })

    describe('mint tokens', () => {
      let shortOtoken: MockOtokenInstance

      before(async () => {
        const expiryTime = new BigNumber(60 * 60 * 24) // after 1 day
        shortOtoken = await MockOtoken.new()

        // initialize new short otoken
        await shortOtoken.init(
          addressBook.address,
          weth.address,
          usdc.address,
          usdc.address,
          createTokenAmount(200),
          new BigNumber(await time.latest()).plus(expiryTime),
          true,
        )
        // whitelist the token
        await whitelist.whitelistOtoken(shortOtoken.address)
        // open a new naked margin vault
        // increment the vault counter
        vaultCounter += 1
        const actionArgs = [
          {
            actionType: ActionType.OpenVault,
            owner: accountOwner1,
            secondAddress: ZERO_ADDR,
            asset: ZERO_ADDR,
            // vault 2
            vaultId: vaultCounter.toString(),
            amount: '0',
            // not naked margin
            index: '1',
            data: ZERO_ADDR,
          },
        ]
        await controllerProxy.operate(actionArgs, {from: accountOwner1})
      })

      it('should not mint tokens in a vault with no collateral', async () => {
        const amountToMint = createTokenAmount(1)
        const actionArgs = [
          {
            actionType: ActionType.MintShortOption,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: shortOtoken.address,
            vaultId: vaultCounter.toString(),
            amount: amountToMint,
            index: '0',
            data: ZERO_ADDR,
          },
        ]
        await oracle.setRealTimePrice(weth.address, new BigNumber('1000e8'))
        await expectRevert(
          controllerProxy.operate(actionArgs, {from: accountOwner1}),
          'Controller: invalid final vault state',
        )
      })

      it('should mint tokens in a collateralized vault', async () => {
        const collateralToDeposit = createTokenAmount(100, usdcDecimals)
        const amountToMint = createTokenAmount(1)

        const actionArgs = [
          {
            actionType: ActionType.DepositCollateral,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: usdc.address,
            vaultId: vaultCounter.toString(),
            amount: collateralToDeposit,
            index: '0',
            data: ZERO_ADDR,
          },
          {
            actionType: ActionType.MintShortOption,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: shortOtoken.address,
            vaultId: vaultCounter.toString(),
            amount: amountToMint,
            index: '0',
            data: ZERO_ADDR,
          },
        ]

        await usdc.approve(marginPool.address, collateralToDeposit, {from: accountOwner1})
        await controllerProxy.operate(actionArgs, {from: accountOwner1})
        assert.equal((await shortOtoken.balanceOf(accountOwner1)).toString(), amountToMint)
      })

      it('should revert if not enough collateral', async () => {
        const collateralToDeposit = createTokenAmount(1, usdcDecimals)
        const amountToMint = createTokenAmount(10)

        const actionArgs = [
          {
            actionType: ActionType.DepositCollateral,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: usdc.address,
            vaultId: vaultCounter.toString(),
            amount: collateralToDeposit,
            index: '0',
            data: ZERO_ADDR,
          },
          {
            actionType: ActionType.MintShortOption,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: shortOtoken.address,
            vaultId: vaultCounter.toString(),
            amount: amountToMint,
            index: '0',
            data: ZERO_ADDR,
          },
        ]
        await usdc.approve(marginPool.address, collateralToDeposit, {from: accountOwner1})
        await expectRevert(
          controllerProxy.operate(actionArgs, {from: accountOwner1}),
          'Controller: invalid final vault state',
        )
      })
    })

    describe('_liquidate', async () => {
      let shortOtoken: MockOtokenInstance
      let now: BigNumber
      before(async () => {
        vaultCounter += 1
        const expiryTime = new BigNumber(60 * 60 * 24) // after 1 day
        shortOtoken = await MockOtoken.new()
        now = new BigNumber(await time.latest())
        // initialize new short otoken
        // weth put with usdc collateral
        await shortOtoken.init(
          addressBook.address,
          weth.address,
          usdc.address,
          usdc.address,
          createTokenAmount(200),
          now.plus(expiryTime),
          true,
        )
        const amountToMint = createTokenAmount(1)
        await shortOtoken.mintOtoken(accountOwner2, amountToMint)
        await shortOtoken.approve(marginPool.address, amountToMint, {from: accountOwner2})
        // accountOwner1 deposits collateral and mints short tokens
        const collateralToDeposit = createTokenAmount(100, usdcDecimals)

        const actionArgs = [
          {
            actionType: ActionType.OpenVault,
            owner: accountOwner1,
            secondAddress: ZERO_ADDR,
            asset: ZERO_ADDR,
            vaultId: vaultCounter.toString(),
            amount: '0',
            // naked margin
            index: '1',
            data: ZERO_ADDR,
          },
          {
            actionType: ActionType.DepositCollateral,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: usdc.address,
            vaultId: vaultCounter.toString(),
            amount: collateralToDeposit,
            index: '0',
            data: ZERO_ADDR,
          },
          {
            actionType: ActionType.MintShortOption,
            owner: accountOwner1,
            secondAddress: accountOwner1,
            asset: shortOtoken.address,
            vaultId: vaultCounter.toString(),
            amount: amountToMint,
            index: '0',
            data: ZERO_ADDR,
          },
        ]

        await oracle.setRealTimePrice(weth.address, new BigNumber('1000e8'))
        await whitelist.whitelistOtoken(shortOtoken.address)
        await usdc.approve(marginPool.address, collateralToDeposit, {from: accountOwner1})
        await controllerProxy.operate(actionArgs, {from: accountOwner1})
      })

      it('should not revert', async () => {
        const roundId = 15
        await time.increase(time.duration.hours(12))
        // set historical price for one minute after the minting
        await oracle.setHistoricalPrice(weth.address, roundId, new BigNumber('1e8'), now.plus(60))

        const actionArgs = [
          {
            actionType: ActionType.Liquidate,
            owner: accountOwner1,
            secondAddress: ZERO_ADDR,
            asset: ZERO_ADDR,
            vaultId: vaultCounter.toString(),
            amount: '0',
            // roundId
            index: roundId.toString(),
            data: ZERO_ADDR,
          },
        ]

        await controllerProxy.operate(actionArgs, {from: accountOwner2})
        assert.equal(5, 5)
      })
    })
  },
)

// it('should not be liquidatable if short otoken is expired')

// it('should not be liquidatable if not naked margin')

// it('should not be liquidatable if no short otoken')

// it('should not be liquidatable if adjusted recently')

// it('should be liquidatable for the full amount if the auction period has ended')

// it('should be able to partially liquidate a vault')

// it('should not be allowed to pay back more than the vault requires')

// it('should not be allowed to partially liquidate *and* leave less than the dust limit')