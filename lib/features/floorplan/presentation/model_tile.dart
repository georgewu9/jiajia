// 模型 tile 的统一外观（v0.1.38）：所有菜单网格共用这一处。
//
// 颜色区分（需求 6）：
//   · 系统模型（ModelSpec 目录来的）→ 现状：raised 底 + line 细边 + 无角标；
//   · 用户模型（LibModelsStore 来的）→ 翡翠绿边框（JiajiaColors.accent）+
//     右上角「用户」角标（accentSoft 底 / accent 字）。
// 长按任意 tile = 导出单件模型 JSON（回调由各 sheet 提供）。
import 'package:flutter/material.dart';

import '../../../app/i18n.dart';
import '../../../app/theme.dart';

class ModelTile extends StatelessWidget {
  final String label;
  final String specText;

  /// 原 app 2D 图标（assets/models2d/…）；null → 用 [fallbackIcon]。
  final String? iconPath;
  final IconData fallbackIcon;

  /// 是否用户模型（LibModelsStore）；true → 翡翠绿边 + 「用户」角标。
  final bool isUser;

  /// CC-BY 署名角标（系统素材 fountain 等）。
  final String? credit;

  final VoidCallback? onTap;

  /// 长按导出单件 JSON；null = 不可导出（导入 tile 等）。
  final VoidCallback? onLongPress;

  const ModelTile({
    super.key,
    required this.label,
    required this.specText,
    required this.fallbackIcon,
    this.iconPath,
    this.isUser = false,
    this.credit,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isUser ? JiajiaColors.accent : JiajiaColors.line;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: JiajiaColors.raised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: isUser ? 1.4 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                if (iconPath != null)
                  Image.asset(
                    iconPath!,
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(
                      fallbackIcon,
                      color: JiajiaColors.text2,
                      size: 26,
                    ),
                  )
                else
                  Icon(
                    fallbackIcon,
                    color: isUser ? JiajiaColors.accent : JiajiaColors.accent,
                    size: 26,
                  ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: JiajiaColors.text1,
                    fontSize: 12,
                  ),
                ),
                Text(
                  specText,
                  style: const TextStyle(
                    color: JiajiaColors.text2,
                    fontSize: 9,
                  ),
                ),
                if (credit != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: JiajiaColors.accentSoft,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'CC-BY',
                      style: TextStyle(
                        color: JiajiaColors.accent,
                        fontSize: 8,
                        height: 1.1,
                      ),
                    ),
                  ),
              ],
            ),
            if (isUser)
              Positioned(
                top: 0,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: JiajiaColors.accentSoft,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: JiajiaColors.accent, width: 0.6),
                  ),
                  child: Text(
                    t('user_badge'),
                    style: const TextStyle(
                      color: JiajiaColors.accent,
                      fontSize: 8,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
