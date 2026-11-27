import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/radio_station.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/page_header.dart';
import 'radio_controller.dart';

class RadioPage extends StatefulWidget {
  const RadioPage({super.key});

  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RadioController>().ensureCountries();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RadioController radio = context.watch<RadioController>();
    final List<RadioStation> stations = radio.visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PageHeader(
          title: '电台',
          subtitle: radio.favoritesOnly
              ? '收藏 ${radio.favorites.length} 个电台'
              : '数据来源 radio-browser.info · 共 ${radio.stations.length} 个电台',
          actions: <Widget>[
            IconButton(
              tooltip: '只看收藏',
              onPressed: () {
                if (radio.favoritesOnly) {
                  radio.loadTop();
                } else {
                  radio.showFavorites();
                }
              },
              icon: Icon(
                radio.favoritesOnly
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: radio.favoritesOnly ? AppColors.accent : null,
              ),
            ),
            IconButton(
              tooltip: '刷新热门电台',
              onPressed: radio.loading ? null : radio.loadTop,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: radio.search,
                  decoration: const InputDecoration(
                    hintText: '搜索电台名称，例如 jazz、lofi、BBC',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _CountryPicker(radio: radio),
            ],
          ),
        ),
        if (radio.loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (radio.error != null)
          NoticeBanner(message: radio.error!, icon: Icons.wifi_off_rounded),
        Expanded(
          child: stations.isEmpty
              ? EmptyHint(
                  icon: Icons.radio_rounded,
                  title: radio.favoritesOnly ? '还没有收藏电台' : '暂时没有电台',
                  description: radio.favoritesOnly
                      ? '在热门列表里点击右侧星标即可收藏，收藏会保存在本地。'
                      : '热门列表拉取失败时可以点右上角刷新重试。',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: stations.length,
                  itemBuilder: (BuildContext context, int index) {
                    final RadioStation station = stations[index];
                    return _StationRow(
                      station: station,
                      favorite: radio.isFavorite(station.uuid),
                      onTap: () => radio.play(station),
                      onToggleFavorite: () => radio.toggleFavorite(station),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CountryPicker extends StatelessWidget {
  const _CountryPicker({required this.radio});

  final RadioController radio;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      // 必须限宽：DropdownButton 的固有宽度取决于最长的一项（例如
      // "United States of America"），在窄屏的 Row 里会把搜索框挤成 0 宽并溢出。
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: radio.country,
          isDense: true,
          isExpanded: true,
          dropdownColor: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          hint: const Text('国家', style: TextStyle(fontSize: 12.5)),
          onChanged: radio.filterByCountry,
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: '',
              child: Text(
                '全部',
                style: TextStyle(fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...radio.countries.map(
              (MapEntry<String, String> entry) => DropdownMenuItem<String>(
                value: entry.key,
                child: Text(
                  entry.value,
                  style: const TextStyle(fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationRow extends StatefulWidget {
  const _StationRow({
    required this.station,
    required this.favorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final RadioStation station;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  State<_StationRow> createState() => _StationRowState();
}

class _StationRowState extends State<_StationRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          color: _hover
              ? AppColors.surfaceHigh.withValues(alpha: 0.6)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: <Widget>[
              CoverArt(
                source: widget.station.favicon,
                size: 44,
                fallbackSeed: widget.station.name,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.station.subtitle.isEmpty
                          ? (widget.station.tags ?? '网络电台')
                          : widget.station.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hover)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: AppColors.accent,
                  ),
                ),
              IconButton(
                tooltip: widget.favorite ? '取消收藏' : '收藏',
                onPressed: widget.onToggleFavorite,
                icon: Icon(
                  widget.favorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 19,
                  color: widget.favorite
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
