const yargs = require("yargs");

const UniswapV2Pricer = artifacts.require("UniswapV2Pricer.sol");

module.exports = async function(callback) {
    try {
        const options = yargs
            .usage("Usage: --network <network> --bot <bot> --asset <asset> --priceEmitter <priceEmitter> --oracle <oracle> --uniswapV2Pair <uniswapV2Pair> --denominationToken <denominationToken> --gas <gasPrice>")
            .option("network", { describe: "Network name", type: "string", demandOption: true })
            .option("bot", { describe: "Bot address", type: "string", demandOption: true })
            .option("asset", { describe: "Asset address", type: "string", demandOption: true })
            .option("priceEmitter", { describe: "UniswapV2 Price Emitter address", type: "string", demandOption: true })
            .option("oracle", { describe: "oracle module address", type: "string", demandoption: true })
            .option("uniswapV2Pair", { describe: "Uniswap V2 asset pairing to price", type: "string", demandoption: true })
            .option("denominationToken", { describe: "Denomination token address", type: "string", demandoption: true })
            .option("gas", { describe: "Gas price in WEI", type: "string", demandOption: false })
            .argv;

        console.log(`Deploying UniswapV2 pricer contract on ${options.network} 🍕`)

        const tx = await UniswapV2Pricer.new(options.bot, options.asset, options.priceEmitter, options.uniswapV2Pair, options.denominationToken, options.oracle, {gasPrice: options.gas});

        console.log("UniswapV2 pricer deployed! 🎉");
        console.log(`Transaction hash: ${tx.transactionHash}`);
        console.log(`Deployed contract address: ${tx.address}`);

        callback();
    }
    catch(err) {
        callback(err);
    }
} 
