/**
 * 分类与过滤器模型
 */
export interface CategoryItem {
  typeId: string;          // 分类 ID
  typeName: string;        // 分类名称 (如 "全部", "热血", "都市", "逆袭")
  isSelected?: boolean;
}

export interface FilterOption {
  key: string;
  name: string;
  value: string;
}

export interface FilterGroup {
  name: string;
  key: string;
  options: FilterOption[];
}
