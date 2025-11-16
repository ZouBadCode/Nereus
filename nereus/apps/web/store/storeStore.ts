import { create } from "zustand";
export type Market = {
  address: string;
  digest: string;
  pid: number; // 自定义字段示例
};

import { gqlQuery } from "@/utils/gql";
import { market } from "./move/package";

type StoreState = {
  marketList: Market[];
  queryMarkets: () => Promise<void>;
};

export const storeStore = create<StoreState>((set) => ({
  marketList: [],
  queryMarkets: async () => {
    const { data } = await gqlQuery(`
      {
        objects(filter: { type: "${market}::market" }) {
          nodes {
            address
            digest
            asMoveObject {
              contents {
                json
              }
            }
          }
        }
      }
    `);

    console.log("marketList", data);
  },
}));
