import {
  CronCapability,
  EVMClient,
  getNetwork,
  encodeCallMsg,
  bytesToHex,
  LAST_FINALIZED_BLOCK_NUMBER,
  type Runtime,
  Runner,
  decodeJson,
  handler,
  HTTPCapability,
  HTTPPayload,
  HTTPSendRequester,
  HTTPClient,
  consensusMedianAggregation,
  hexToBase64,
  TxStatus,
} from "@chainlink/cre-sdk";
import {
  type Address,
  encodeFunctionData,
  decodeFunctionResult,
  parseAbi,
  zeroAddress,
  encodeAbiParameters,
  parseAbiParameters,
} from "viem";
import { number, z } from "zod";

const configSchema = z.object({
  priceFeeds: z.record(
    z.string(),
    z.object({
      proxyAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/i),
      chainSelectorName: z.string(),
      chainId: z.number().int().positive(),
    }),
  ),
  targetContract: z.object({
    address: z.string().regex(/^0x[a-fA-F0-9]{40}$/i),
    chainSelectorName: z.string(),
    chainId: z.number().int().positive(),
    gasLimit: z.string(),
  }),
});

type Config = z.infer<typeof configSchema>;

type RequestData = {
  token: string;
};

type etherscanResponse = {
  status: string;
  result: string;
  message: string;
};

const priceFeedAbi = parseAbi([
  "function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
]);

const recordAbiType = [
  {
    type: "tuple",
    name: "record",
    components: [
      { type: "string", name: "token" },
      { type: "uint256", name: "price" },
      { type: "uint256", name: "blockNumber" },
      { type: "uint256", name: "timestamp" },
    ],
  },
] as const;

const fetchAndParse = (
  sendRequester: HTTPSendRequester,
  apiKey: string,
  updatedAt: bigint,
  chainId: number,
): number => {
  const url = `https://api.etherscan.io/v2/api?chainid=${chainId}&module=block&action=getblocknobytime&timestamp=${updatedAt}&closest=before&apikey=${apiKey}`;
  // 1. Construct the request
  const req = {
    url,
    method: "GET" as const,
  };

  // 2. Send the request using the provided sendRequester
  const resp = sendRequester.sendRequest(req).result();

  if (resp.statusCode !== 200) {
    throw new Error(`API returned status ${resp.statusCode}`);
  }

  // 3. Parse the raw JSON into our ExternalApiResponse type
  const bodyText = new TextDecoder().decode(resp.body);
  const externalResp = JSON.parse(bodyText) as etherscanResponse;
  const numb = parseInt(externalResp.result);

  return numb;
};

// Callback function that runs when an HTTP request is received
const onHttpTrigger = (
  runtime: Runtime<Config>,
  payload: HTTPPayload,
): string => {
  const httpClient = new HTTPClient();
  const requestData = decodeJson(payload.input) as RequestData;

  runtime.log(`Received HTTP request: ${JSON.stringify(requestData)}`);

  if (!requestData.token) throw new Error("Error: 'token' field is required");

  const tokenUpper = requestData.token.toUpperCase();
  const feed = runtime.config.priceFeeds[tokenUpper];
  if (!feed)
    throw new Error(`Error: No price feed configured for ${requestData.token}`);
  //get network
  const network = getNetwork({
    chainFamily: "evm",
    chainSelectorName: feed.chainSelectorName,
    isTestnet: true,
  });

  if (!network) {
    throw new Error(`Network not found: ${feed.chainSelectorName}`);
  }
  // Create EVM client with chain selector
  const evmClient = new EVMClient(network!.chainSelector.selector);

  // Encode the function call
  const callData = encodeFunctionData({
    abi: priceFeedAbi,
    functionName: "latestRoundData",
    args: [], // No arguments for this function
  });
  const contractCall = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: feed.proxyAddress as Address,
        data: callData,
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();

  const [roundId, answer, startedAt, updatedAt, answeredInRound] =
    decodeFunctionResult({
      abi: priceFeedAbi,
      functionName: "latestRoundData",
      data: bytesToHex(contractCall.data),
    });

  runtime.log(`Successfully read storage value: ${roundId}, answer: ${answer}`);

  const secret = runtime.getSecret({ id: "CRE_ETHERSCAN_API_KEY" }).result();
  const apiKey = secret.value;

  const aggregatedBlockNumber = httpClient
    .sendRequest(
      runtime,
      fetchAndParse,
      consensusMedianAggregation<number>(),
    )(apiKey, updatedAt, feed.chainId)
    .result();

  runtime.log(
    `Aggregated Etherscan block number result: ${aggregatedBlockNumber}`,
  );

  const blockNum = BigInt(aggregatedBlockNumber);

  const reportData = encodeAbiParameters(recordAbiType, [
    {
      token: tokenUpper,
      price: BigInt(answer),
      blockNumber: BigInt(blockNum),
      timestamp: BigInt(updatedAt),
    },
  ]);

  runtime.log(`${reportData}`);

  const reportResponse = runtime
    .report({
      encodedPayload: hexToBase64(reportData),
      encoderName: "evm",
      signingAlgo: "ecdsa",
      hashingAlgo: "keccak256",
    })
    .result();

  const writeResult = evmClient
    .writeReport(runtime, {
      receiver: runtime.config.targetContract.address as Address,
      report: reportResponse,
      gasConfig: { gasLimit: runtime.config.targetContract.gasLimit },
    })
    .result();

  if (writeResult.txStatus === TxStatus.SUCCESS) {
    const txHash = bytesToHex(writeResult.txHash || new Uint8Array(32));
    runtime.log(`Snapshot written on-chain! Tx: ${txHash}`);
    return txHash;
  }
  throw new Error(
    `Write failed: ${writeResult.txStatus} - ${writeResult.errorMessage || "unknown"}`,
  );
};

const initWorkflow = (config: Config) => {
  const httpTrigger = new HTTPCapability();

  return [
    handler(
      httpTrigger.trigger({
        /*  authorizedKeys: [
          {
            type: "KEY_TYPE_ECDSA_EVM",
            publicKey: config.authorizedEVMAddress,
          },
          ],*/
      }),
      onHttpTrigger,
    ),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
