import 'package:flutter/material.dart';
import '../navigation/app_navigation.dart';
import '../navigation/route_paths.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../navigation/wallet_onboarding_navigation.dart';
import '../services/wallet_state_manager.dart';
import '../providers/app_provider.dart';
import '../services/secure_storage.dart';
import '../services/security_settings_manager.dart';
import '../wallet/wallet_repository.dart';
import '../wallet/local_import_adapter.dart';

class ImportWalletScreen extends StatefulWidget {
  final Map<String, dynamic>? qrArguments;
  
  const ImportWalletScreen({
    super.key,
    this.qrArguments,
  });

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  // 12 controllers for 12 seed phrase words
  late List<TextEditingController> _wordControllers;
  late List<FocusNode> _focusNodes;
  bool _isLoading = false;
  bool _showErrorModal = false;
  String _errorMessage = '';
  String walletName = 'Imported wallet 1';
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;
  
  // Word filtering for suggestions
  List<String> _filteredWords = [];
  String _currentFilter = '';
  int _currentlyEditingIndex = -1;
  
  // Word visibility control
  List<bool> _wordVisibility = List.filled(12, false); // Default hidden
  bool _allWordsVisible = false;
  
  // Word validation
  List<bool> _wordValidation = List.filled(12, true); // Track validation state for each word
  bool _hasValidationErrors = false;
  
  // BIP39 wordlist (2048 words)
  static const List<String> _bip39Words = [
    'abandon', 'ability', 'able', 'about', 'above', 'absent', 'absorb', 'abstract', 'absurd', 'abuse', 'access', 
    'accident', 'account', 'accuse', 'achieve', 'acid', 'acoustic', 'acquire', 'across', 'act', 'action', 
    'actor', 'actress', 'actual', 'adapt', 'add', 'addict', 'address', 'adjust', 'admit', 'adult', 'advance', 
    'advice', 'aerobic', 'affair', 'afford', 'afraid', 'again', 'age', 'agent', 'agree', 'ahead', 'aim', 'air', 
    'airport', 'aisle', 'alarm', 'album', 'alcohol', 'alert', 'alien', 'all', 'alley', 'allow', 'almost', 
    'alone', 'alpha', 'already', 'also', 'alter', 'always', 'amateur', 'amazing', 'among', 'amount', 'amused', 
    'analyst', 'anchor', 'ancient', 'anger', 'angle', 'angry', 'animal', 'ankle', 'announce', 'annual', 
    'another', 'answer', 'antenna', 'antique', 'anxiety', 'any', 'apart', 'apology', 'appear', 'apple', 
    'approve', 'april', 'arch', 'arctic', 'area', 'arena', 'argue', 'arm', 'armed', 'armor', 'army', 'around', 
    'arrange', 'arrest', 'arrive', 'arrow', 'art', 'artefact', 'artist', 'artwork', 'ask', 'aspect', 'assault', 
    'asset', 'assist', 'assume', 'asthma', 'athlete', 'atom', 'attack', 'attend', 'attitude', 'attract', 
    'auction', 'audit', 'august', 'aunt', 'author', 'auto', 'autumn', 'average', 'avocado', 'avoid', 'awake', 
    'aware', 'away', 'awesome', 'awful', 'awkward', 'axis', 'baby', 'bachelor', 'bacon', 'badge', 'bag', 
    'balance', 'balcony', 'ball', 'bamboo', 'banana', 'banner', 'bar', 'barely', 'bargain', 'barrel', 'base', 
    'basic', 'basket', 'battle', 'beach', 'bean', 'beauty', 'because', 'become', 'beef', 'before', 'begin', 
    'behave', 'behind', 'believe', 'below', 'belt', 'bench', 'benefit', 'best', 'betray', 'better', 'between', 
    'beyond', 'bicycle', 'bid', 'bike', 'bind', 'biology', 'bird', 'birth', 'bitter', 'black', 'blade', 'blame', 
    'blanket', 'blast', 'bleak', 'bless', 'blind', 'blood', 'blossom', 'blouse', 'blue', 'blur', 'blush', 
    'board', 'boat', 'body', 'boil', 'bomb', 'bone', 'bonus', 'book', 'boost', 'border', 'boring', 'borrow', 
    'boss', 'bottom', 'bounce', 'box', 'boy', 'bracket', 'brain', 'brand', 'brass', 'brave', 'bread', 'breeze', 
    'brick', 'bridge', 'brief', 'bright', 'bring', 'brisk', 'broccoli', 'broken', 'bronze', 'broom', 'brother', 
    'brown', 'brush', 'bubble', 'buddy', 'budget', 'buffalo', 'build', 'bulb', 'bulk', 'bullet', 'bundle', 
    'bunker', 'burden', 'burger', 'burst', 'bus', 'business', 'busy', 'butter', 'buyer', 'buzz', 'cabbage', 
    'cabin', 'cable', 'cactus', 'cage', 'cake', 'call', 'calm', 'camera', 'camp', 'can', 'canal', 'cancel', 
    'candy', 'cannon', 'canoe', 'canvas', 'canyon', 'capable', 'capital', 'captain', 'car', 'carbon', 'card', 
    'cargo', 'carpet', 'carry', 'cart', 'case', 'cash', 'casino', 'castle', 'casual', 'cat', 'catalog', 'catch', 
    'category', 'cattle', 'caught', 'cause', 'caution', 'cave', 'ceiling', 'celery', 'cement', 'census', 
    'century', 'cereal', 'certain', 'chair', 'chalk', 'champion', 'change', 'chaos', 'chapter', 'charge', 
    'chase', 'chat', 'cheap', 'check', 'cheese', 'chef', 'cherry', 'chest', 'chicken', 'chief', 'child', 
    'chimney', 'choice', 'choose', 'chronic', 'chuckle', 'chunk', 'churn', 'cigar', 'cinnamon', 'circle', 
    'citizen', 'city', 'civil', 'claim', 'clap', 'clarify', 'claw', 'clay', 'clean', 'clerk', 'clever', 'click', 
    'client', 'cliff', 'climb', 'clinic', 'clip', 'clock', 'clog', 'close', 'cloth', 'cloud', 'clown', 'club', 
    'clump', 'cluster', 'clutch', 'coach', 'coast', 'coconut', 'code', 'coffee', 'coil', 'coin', 'collect', 
    'color', 'column', 'combine', 'come', 'comfort', 'comic', 'common', 'company', 'concert', 'conduct', 
    'confirm', 'congress', 'connect', 'consider', 'control', 'convince', 'cook', 'cool', 'copper', 'copy', 
    'coral', 'core', 'corn', 'correct', 'cost', 'cotton', 'couch', 'country', 'couple', 'course', 'cousin', 
    'cover', 'coyote', 'crack', 'cradle', 'craft', 'cram', 'crane', 'crash', 'crater', 'crawl', 'crazy', 'cream', 
    'credit', 'creek', 'crew', 'cricket', 'crime', 'crisp', 'critic', 'crop', 'cross', 'crouch', 'crowd', 
    'crucial', 'cruel', 'cruise', 'crumble', 'crunch', 'crush', 'cry', 'crystal', 'cube', 'culture', 'cup', 
    'cupboard', 'curious', 'current', 'curtain', 'curve', 'cushion', 'custom', 'cute', 'cycle', 'dad', 'damage', 
    'damp', 'dance', 'danger', 'daring', 'dash', 'daughter', 'dawn', 'day', 'deal', 'debate', 'debris', 'decade', 
    'december', 'decide', 'decline', 'decorate', 'decrease', 'deer', 'defense', 'define', 'defy', 'degree', 
    'delay', 'deliver', 'demand', 'demise', 'denial', 'dentist', 'deny', 'depart', 'depend', 'deposit', 'depth', 
    'deputy', 'derive', 'describe', 'desert', 'design', 'desk', 'despair', 'destroy', 'detail', 'detect', 
    'develop', 'device', 'devote', 'diagram', 'dial', 'diamond', 'diary', 'dice', 'diesel', 'diet', 'differ', 
    'digital', 'dignity', 'dilemma', 'dinner', 'dinosaur', 'direct', 'dirt', 'disagree', 'discover', 'disease', 
    'dish', 'dismiss', 'disorder', 'display', 'distance', 'divert', 'divide', 'divorce', 'dizzy', 'doctor', 
    'document', 'dog', 'doll', 'dolphin', 'domain', 'donate', 'donkey', 'donor', 'door', 'dose', 'double', 
    'dove', 'draft', 'dragon', 'drama', 'drastic', 'draw', 'dream', 'dress', 'drift', 'drill', 'drink', 'drip', 
    'drive', 'drop', 'drum', 'dry', 'duck', 'dumb', 'dune', 'during', 'dust', 'dutch', 'duty', 'dwarf', 
    'dynamic', 'eager', 'eagle', 'early', 'earn', 'earth', 'easily', 'east', 'easy', 'echo', 'ecology', 
    'economy', 'edge', 'edit', 'educate', 'effort', 'egg', 'eight', 'either', 'elbow', 'elder', 'electric', 
    'elegant', 'element', 'elephant', 'elevator', 'elite', 'else', 'embark', 'embody', 'embrace', 'emerge', 
    'emotion', 'employ', 'empower', 'empty', 'enable', 'enact', 'end', 'endless', 'endorse', 'enemy', 'energy', 
    'enforce', 'engage', 'engine', 'enhance', 'enjoy', 'enlist', 'enough', 'enrich', 'enroll', 'ensure', 'enter', 
    'entire', 'entry', 'envelope', 'episode', 'equal', 'equip', 'era', 'erase', 'erode', 'erosion', 'error', 
    'erupt', 'escape', 'essay', 'essence', 'estate', 'eternal', 'ethics', 'evidence', 'evil', 'evoke', 'evolve', 
    'exact', 'example', 'excess', 'exchange', 'excite', 'exclude', 'excuse', 'execute', 'exercise', 'exhaust', 
    'exhibit', 'exile', 'exist', 'exit', 'exotic', 'expand', 'expect', 'expire', 'explain', 'expose', 'express', 
    'extend', 'extra', 'eye', 'eyebrow', 'fabric', 'face', 'faculty', 'fade', 'faint', 'faith', 'fall', 'false', 
    'fame', 'family', 'famous', 'fan', 'fancy', 'fantasy', 'farm', 'fashion', 'fat', 'fatal', 'father', 
    'fatigue', 'fault', 'favorite', 'feature', 'february', 'federal', 'fee', 'feed', 'feel', 'female', 'fence', 
    'festival', 'fetch', 'fever', 'few', 'fiber', 'fiction', 'field', 'figure', 'file', 'film', 'filter', 
    'final', 'find', 'fine', 'finger', 'finish', 'fire', 'firm', 'first', 'fiscal', 'fish', 'fit', 'fitness', 
    'fix', 'flag', 'flame', 'flash', 'flat', 'flavor', 'flee', 'flight', 'flip', 'float', 'flock', 'floor', 
    'flower', 'fluid', 'flush', 'fly', 'foam', 'focus', 'fog', 'foil', 'fold', 'follow', 'food', 'foot', 'force', 
    'forest', 'forget', 'fork', 'fortune', 'forum', 'forward', 'fossil', 'foster', 'found', 'fox', 'fragile', 
    'frame', 'frequent', 'fresh', 'friend', 'fringe', 'frog', 'front', 'frost', 'frown', 'frozen', 'fruit', 
    'fuel', 'fun', 'funny', 'furnace', 'fury', 'future', 'gadget', 'gain', 'galaxy', 'gallery', 'game', 'gap', 
    'garage', 'garbage', 'garden', 'garlic', 'garment', 'gas', 'gasp', 'gate', 'gather', 'gauge', 'gaze', 
    'general', 'genius', 'genre', 'gentle', 'genuine', 'gesture', 'ghost', 'giant', 'gift', 'giggle', 'ginger', 
    'giraffe', 'girl', 'give', 'glad', 'glance', 'glare', 'glass', 'glide', 'glimpse', 'globe', 'gloom', 'glory', 
    'glove', 'glow', 'glue', 'goat', 'goddess', 'gold', 'good', 'goose', 'gorilla', 'gospel', 'gossip', 'govern', 
    'gown', 'grab', 'grace', 'grain', 'grant', 'grape', 'grass', 'gravity', 'great', 'green', 'grid', 'grief', 
    'grit', 'grocery', 'group', 'grow', 'grunt', 'guard', 'guess', 'guide', 'guilt', 'guitar', 'gun', 'gym', 
    'habit', 'hair', 'half', 'hammer', 'hamster', 'hand', 'happy', 'harbor', 'hard', 'harsh', 'harvest', 'hat', 
    'have', 'hawk', 'hazard', 'head', 'health', 'heart', 'heavy', 'hedgehog', 'height', 'hello', 'helmet', 
    'help', 'hen', 'hero', 'hidden', 'high', 'hill', 'hint', 'hip', 'hire', 'history', 'hobby', 'hockey', 'hold', 
    'hole', 'holiday', 'hollow', 'home', 'honey', 'hood', 'hope', 'horn', 'horror', 'horse', 'hospital', 'host', 
    'hotel', 'hour', 'hover', 'hub', 'huge', 'human', 'humble', 'humor', 'hundred', 'hungry', 'hunt', 'hurdle', 
    'hurry', 'hurt', 'husband', 'hybrid', 'ice', 'icon', 'idea', 'identify', 'idle', 'ignore', 'ill', 'illegal', 
    'illness', 'image', 'imitate', 'immense', 'immune', 'impact', 'impose', 'improve', 'impulse', 'inch', 
    'include', 'income', 'increase', 'index', 'indicate', 'indoor', 'industry', 'infant', 'inflict', 'inform', 
    'inhale', 'inherit', 'initial', 'inject', 'injury', 'inmate', 'inner', 'innocent', 'input', 'inquiry', 
    'insane', 'insect', 'inside', 'inspire', 'install', 'intact', 'interest', 'into', 'invest', 'invite', 
    'involve', 'iron', 'island', 'isolate', 'issue', 'item', 'ivory', 'jacket', 'jaguar', 'jar', 'jazz', 
    'jealous', 'jeans', 'jelly', 'jewel', 'job', 'join', 'joke', 'journey', 'joy', 'judge', 'juice', 'jump', 
    'jungle', 'junior', 'junk', 'just', 'kangaroo', 'keen', 'keep', 'ketchup', 'key', 'kick', 'kid', 'kidney', 
    'kind', 'kingdom', 'kiss', 'kit', 'kitchen', 'kite', 'kitten', 'kiwi', 'knee', 'knife', 'knock', 'know', 
    'lab', 'label', 'labor', 'ladder', 'lady', 'lake', 'lamp', 'language', 'laptop', 'large', 'later', 'latin', 
    'laugh', 'laundry', 'lava', 'law', 'lawn', 'lawsuit', 'layer', 'lazy', 'leader', 'leaf', 'learn', 'leave', 
    'lecture', 'left', 'leg', 'legal', 'legend', 'leisure', 'lemon', 'lend', 'length', 'lens', 'leopard', 
    'lesson', 'letter', 'level', 'liar', 'liberty', 'library', 'license', 'life', 'lift', 'light', 'like', 
    'limb', 'limit', 'link', 'lion', 'liquid', 'list', 'little', 'live', 'lizard', 'load', 'loan', 'lobster', 
    'local', 'lock', 'logic', 'lonely', 'long', 'loop', 'lottery', 'loud', 'lounge', 'love', 'loyal', 'lucky', 
    'luggage', 'lumber', 'lunar', 'lunch', 'luxury', 'lyrics', 'machine', 'mad', 'magic', 'magnet', 'maid', 
    'mail', 'main', 'major', 'make', 'mammal', 'man', 'manage', 'mandate', 'mango', 'mansion', 'manual', 'maple', 
    'marble', 'march', 'margin', 'marine', 'market', 'marriage', 'mask', 'mass', 'master', 'match', 'material', 
    'math', 'matrix', 'matter', 'maximum', 'maze', 'meadow', 'mean', 'measure', 'meat', 'mechanic', 'medal', 
    'media', 'melody', 'melt', 'member', 'memory', 'mention', 'menu', 'mercy', 'merge', 'merit', 'merry', 'mesh', 
    'message', 'metal', 'method', 'middle', 'midnight', 'milk', 'million', 'mimic', 'mind', 'minimum', 'minor', 
    'minute', 'miracle', 'mirror', 'misery', 'miss', 'mistake', 'mix', 'mixed', 'mixture', 'mobile', 'model', 
    'modify', 'mom', 'moment', 'monitor', 'monkey', 'monster', 'month', 'moon', 'moral', 'more', 'morning', 
    'mosquito', 'mother', 'motion', 'motor', 'mountain', 'mouse', 'move', 'movie', 'much', 'muffin', 'mule', 
    'multiply', 'muscle', 'museum', 'mushroom', 'music', 'must', 'mutual', 'myself', 'mystery', 'myth', 'naive', 
    'name', 'napkin', 'narrow', 'nasty', 'nation', 'nature', 'near', 'neck', 'need', 'negative', 'neglect', 
    'neither', 'nephew', 'nerve', 'nest', 'net', 'network', 'neutral', 'never', 'news', 'next', 'nice', 'night', 
    'noble', 'noise', 'nominee', 'noodle', 'normal', 'north', 'nose', 'notable', 'note', 'nothing', 'notice', 
    'novel', 'now', 'nuclear', 'number', 'nurse', 'nut', 'oak', 'obey', 'object', 'oblige', 'obscure', 'observe', 
    'obtain', 'obvious', 'occur', 'ocean', 'october', 'odor', 'off', 'offer', 'office', 'often', 'oil', 'okay', 
    'old', 'olive', 'olympic', 'omit', 'once', 'one', 'onion', 'online', 'only', 'open', 'opera', 'opinion', 
    'oppose', 'option', 'orange', 'orbit', 'orchard', 'order', 'ordinary', 'organ', 'orient', 'original', 
    'orphan', 'ostrich', 'other', 'outdoor', 'outer', 'output', 'outside', 'oval', 'oven', 'over', 'own', 
    'owner', 'oxygen', 'oyster', 'ozone', 'pact', 'paddle', 'page', 'pair', 'palace', 'palm', 'panda', 'panel', 
    'panic', 'panther', 'paper', 'parade', 'parent', 'park', 'parrot', 'party', 'pass', 'patch', 'path', 
    'patient', 'patrol', 'pattern', 'pause', 'pave', 'payment', 'peace', 'peanut', 'pear', 'peasant', 'pelican', 
    'pen', 'penalty', 'pencil', 'people', 'pepper', 'perfect', 'permit', 'person', 'pet', 'phone', 'photo', 
    'phrase', 'physical', 'piano', 'picnic', 'picture', 'piece', 'pig', 'pigeon', 'pill', 'pilot', 'pink', 
    'pioneer', 'pipe', 'pistol', 'pitch', 'pizza', 'place', 'planet', 'plastic', 'plate', 'play', 'please', 
    'pledge', 'pluck', 'plug', 'plunge', 'poem', 'poet', 'point', 'polar', 'pole', 'police', 'pond', 'pony', 
    'pool', 'popular', 'portion', 'position', 'possible', 'post', 'potato', 'pottery', 'poverty', 'powder', 
    'power', 'practice', 'praise', 'predict', 'prefer', 'prepare', 'present', 'pretty', 'prevent', 'price', 
    'pride', 'primary', 'print', 'priority', 'prison', 'private', 'prize', 'problem', 'process', 'produce', 
    'profit', 'program', 'project', 'promote', 'proof', 'property', 'prosper', 'protect', 'proud', 'provide', 
    'public', 'pudding', 'pull', 'pulp', 'pulse', 'pumpkin', 'punch', 'pupil', 'puppy', 'purchase', 'purity', 
    'purpose', 'purse', 'push', 'put', 'puzzle', 'pyramid', 'quality', 'quantum', 'quarter', 'question', 'quick', 
    'quit', 'quiz', 'quote', 'rabbit', 'raccoon', 'race', 'rack', 'radar', 'radio', 'rail', 'rain', 'raise', 
    'rally', 'ramp', 'ranch', 'random', 'range', 'rapid', 'rare', 'rate', 'rather', 'raven', 'raw', 'razor', 
    'ready', 'real', 'reason', 'rebel', 'rebuild', 'recall', 'receive', 'recipe', 'record', 'recycle', 'reduce', 
    'reflect', 'reform', 'refuse', 'region', 'regret', 'regular', 'reject', 'relax', 'release', 'relief', 'rely', 
    'remain', 'remember', 'remind', 'remove', 'render', 'renew', 'rent', 'reopen', 'repair', 'repeat', 'replace', 
    'report', 'require', 'rescue', 'resemble', 'resist', 'resource', 'response', 'result', 'retire', 'retreat', 
    'return', 'reunion', 'reveal', 'review', 'reward', 'rhythm', 'rib', 'ribbon', 'rice', 'rich', 'ride', 
    'ridge', 'rifle', 'right', 'rigid', 'ring', 'riot', 'ripple', 'risk', 'ritual', 'rival', 'river', 'road', 
    'roast', 'robot', 'robust', 'rocket', 'romance', 'roof', 'rookie', 'room', 'rose', 'rotate', 'rough', 
    'round', 'route', 'royal', 'rubber', 'rude', 'rug', 'rule', 'run', 'runway', 'rural', 'sad', 'saddle', 
    'sadness', 'safe', 'sail', 'salad', 'salmon', 'salon', 'salt', 'salute', 'same', 'sample', 'sand', 'satisfy', 
    'satoshi', 'sauce', 'sausage', 'save', 'say', 'scale', 'scan', 'scare', 'scatter', 'scene', 'scheme', 
    'school', 'science', 'scissors', 'scorpion', 'scout', 'scrap', 'screen', 'script', 'scrub', 'sea', 'search', 
    'season', 'seat', 'second', 'secret', 'section', 'security', 'seed', 'seek', 'segment', 'select', 'sell', 
    'seminar', 'senior', 'sense', 'sentence', 'series', 'service', 'session', 'settle', 'setup', 'seven', 
    'shadow', 'shaft', 'shallow', 'share', 'shed', 'shell', 'sheriff', 'shield', 'shift', 'shine', 'ship', 
    'shiver', 'shock', 'shoe', 'shoot', 'shop', 'short', 'shoulder', 'shove', 'shrimp', 'shrug', 'shuffle', 
    'shy', 'sibling', 'sick', 'side', 'siege', 'sight', 'sign', 'silent', 'silk', 'silly', 'silver', 'similar', 
    'simple', 'since', 'sing', 'siren', 'sister', 'situate', 'six', 'size', 'skate', 'sketch', 'ski', 'skill', 
    'skin', 'skirt', 'skull', 'slab', 'slam', 'sleep', 'slender', 'slice', 'slide', 'slight', 'slim', 'slogan', 
    'slot', 'slow', 'slush', 'small', 'smart', 'smile', 'smoke', 'smooth', 'snack', 'snake', 'snap', 'sniff', 
    'snow', 'soap', 'soccer', 'social', 'sock', 'soda', 'soft', 'solar', 'soldier', 'solid', 'solution', 'solve', 
    'someone', 'song', 'soon', 'sorry', 'sort', 'soul', 'sound', 'soup', 'source', 'south', 'space', 'spare', 
    'spatial', 'spawn', 'speak', 'special', 'speed', 'spell', 'spend', 'sphere', 'spice', 'spider', 'spike', 
    'spin', 'spirit', 'split', 'spoil', 'sponsor', 'spoon', 'sport', 'spot', 'spray', 'spread', 'spring', 'spy', 
    'square', 'squeeze', 'squirrel', 'stable', 'stadium', 'staff', 'stage', 'stairs', 'stamp', 'stand', 'start', 
    'state', 'stay', 'steak', 'steel', 'stem', 'step', 'stereo', 'stick', 'still', 'sting', 'stock', 'stomach', 
    'stone', 'stool', 'story', 'stove', 'strategy', 'street', 'strike', 'strong', 'struggle', 'student', 'stuff', 
    'stumble', 'style', 'subject', 'submit', 'subway', 'success', 'such', 'sudden', 'suffer', 'sugar', 'suggest', 
    'suit', 'summer', 'sun', 'sunny', 'sunset', 'super', 'supply', 'supreme', 'sure', 'surface', 'surge', 
    'surprise', 'surround', 'survey', 'suspect', 'sustain', 'swallow', 'swamp', 'swap', 'swarm', 'swear', 
    'sweet', 'swift', 'swim', 'swing', 'switch', 'sword', 'symbol', 'symptom', 'syrup', 'system', 'table', 
    'tackle', 'tag', 'tail', 'talent', 'talk', 'tank', 'tape', 'target', 'task', 'taste', 'tattoo', 'taxi', 
    'teach', 'team', 'tell', 'ten', 'tenant', 'tennis', 'tent', 'term', 'test', 'text', 'thank', 'that', 'theme', 
    'then', 'theory', 'there', 'they', 'thing', 'this', 'thought', 'three', 'thrive', 'throw', 'thumb', 
    'thunder', 'ticket', 'tide', 'tiger', 'tilt', 'timber', 'time', 'tiny', 'tip', 'tired', 'tissue', 'title', 
    'toast', 'tobacco', 'today', 'toddler', 'toe', 'together', 'toilet', 'token', 'tomato', 'tomorrow', 'tone', 
    'tongue', 'tonight', 'tool', 'tooth', 'top', 'topic', 'topple', 'torch', 'tornado', 'tortoise', 'toss', 
    'total', 'tourist', 'toward', 'tower', 'town', 'toy', 'track', 'trade', 'traffic', 'tragic', 'train', 
    'transfer', 'trap', 'trash', 'travel', 'tray', 'treat', 'tree', 'trend', 'trial', 'tribe', 'trick', 
    'trigger', 'trim', 'trip', 'trophy', 'trouble', 'truck', 'true', 'truly', 'trumpet', 'trust', 'truth', 'try', 
    'tube', 'tuition', 'tumble', 'tuna', 'tunnel', 'turkey', 'turn', 'turtle', 'twelve', 'twenty', 'twice', 
    'twin', 'twist', 'two', 'type', 'typical', 'ugly', 'umbrella', 'unable', 'unaware', 'uncle', 'uncover', 
    'under', 'undo', 'unfair', 'unfold', 'unhappy', 'uniform', 'unique', 'unit', 'universe', 'unknown', 'unlock', 
    'until', 'unusual', 'unveil', 'update', 'upgrade', 'uphold', 'upon', 'upper', 'upset', 'urban', 'urge', 
    'usage', 'use', 'used', 'useful', 'useless', 'usual', 'utility', 'vacant', 'vacuum', 'vague', 'valid', 
    'valley', 'valve', 'van', 'vanish', 'vapor', 'various', 'vast', 'vault', 'vehicle', 'velvet', 'vendor', 
    'venture', 'venue', 'verb', 'verify', 'version', 'very', 'vessel', 'veteran', 'viable', 'vibrant', 'vicious', 
    'victory', 'video', 'view', 'village', 'vintage', 'violin', 'virtual', 'virus', 'visa', 'visit', 'visual', 
    'vital', 'vivid', 'vocal', 'voice', 'void', 'volcano', 'volume', 'vote', 'voyage', 'wage', 'wagon', 'wait', 
    'walk', 'wall', 'walnut', 'want', 'warfare', 'warm', 'warrior', 'wash', 'wasp', 'waste', 'water', 'wave', 
    'way', 'wealth', 'weapon', 'wear', 'weasel', 'weather', 'web', 'wedding', 'weekend', 'weird', 'welcome', 
    'west', 'wet', 'whale', 'what', 'wheat', 'wheel', 'when', 'where', 'whip', 'whisper', 'wide', 'width', 
    'wife', 'wild', 'will', 'win', 'window', 'wine', 'wing', 'wink', 'winner', 'winter', 'wire', 'wisdom', 
    'wise', 'wish', 'witness', 'wolf', 'woman', 'wonder', 'wood', 'wool', 'word', 'work', 'world', 'worry', 
    'worth', 'wrap', 'wreck', 'wrestle', 'wrist', 'write', 'wrong', 'yard', 'year', 'yellow', 'you', 'young', 
    'youth', 'zebra', 'zero', 'zone', 'zoo'
  ];

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize 12 controllers and focus nodes for seed phrase words
    _wordControllers = List.generate(12, (index) => TextEditingController());
    _focusNodes = List.generate(12, (index) => FocusNode());
    
    // Setup listeners for auto-navigation between fields
    for (int i = 0; i < 12; i++) {
      _wordControllers[i].addListener(() => _onWordChanged(i));
      _focusNodes[i].addListener(() => _onFocusChanged(i, _focusNodes[i].hasFocus));
    }
    
    _checkExistingWallet();
    _processQRArguments();
    // _suggestNextImportedWalletName(); // Removed as per edit hint
  }

  /// Check if wallet exists and redirect to home if it does
  Future<void> _checkExistingWallet() async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isNotEmpty) {
        print('🔄 Existing wallet found, redirecting to home...');
        if (mounted) {
          AppNavigation.pushNamedAndRemoveUntil(
            context,
            RoutePaths.home,
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('❌ Error checking existing wallet: $e');
    }
  }

  @override
  void dispose() {
    // Dispose all controllers and focus nodes
    for (final controller in _wordControllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _processQRArguments() {
    if (widget.qrArguments != null) {
      final seedPhrase = widget.qrArguments!['seedPhrase'];
      if (seedPhrase != null) {
        print('🌱 QR Seed phrase detected: $seedPhrase');
        _setSeedPhrase(seedPhrase);
      }
    }
  }

  /// Handle word changes and auto-navigation
  void _onWordChanged(int index) {
    final text = _wordControllers[index].text;
    
    // Update current editing index and filter
    setState(() {
      _currentlyEditingIndex = index;
      _currentFilter = text.toLowerCase();
      _updateFilteredWords();
      
      // Validate the current word
      _wordValidation[index] = _isValidBIP39Word(text);
      _validateAllWords(); // Update overall validation state
    });
    
    // If user pasted multiple words from any field, distribute them
    if (text.contains(' ')) {
      _handlePastedText(text, startIndex: index);
      return;
    }
    
    // Auto-navigate to next field when a word is completed and valid
    if (text.isNotEmpty && text.length >= 3 && !text.contains(' ') && _wordValidation[index]) {
      // Check if the word is in BIP39 list for auto-navigation
      if (_bip39Words.contains(text.toLowerCase()) && index < 11) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_wordControllers[index].text.toLowerCase() == text.toLowerCase()) {
            _focusNodes[index + 1].requestFocus();
          }
        });
      }
    }
  }

  /// Update filtered words based on current input
  void _updateFilteredWords() {
    if (_currentFilter.isEmpty) {
      _filteredWords = [];
    } else {
      _filteredWords = _bip39Words
          .where((word) => word.startsWith(_currentFilter))
          .take(8) // Limit to 8 suggestions for UI space
          .toList();
    }
  }

  /// Select a suggested word
  void _selectSuggestedWord(String word) {
    if (_currentlyEditingIndex >= 0 && _currentlyEditingIndex < 12) {
      _wordControllers[_currentlyEditingIndex].text = word;
      
      // Move to next field if not the last one
      if (_currentlyEditingIndex < 11) {
        _focusNodes[_currentlyEditingIndex + 1].requestFocus();
      } else {
        // Last field, unfocus
        FocusScope.of(context).unfocus();
      }
      
      setState(() {
        _filteredWords = [];
        _currentFilter = '';
        _currentlyEditingIndex = -1;
      });
    }
  }

  /// Handle focus changes to manage suggestions
  void _onFocusChanged(int index, bool hasFocus) {
    if (hasFocus) {
      setState(() {
        _currentlyEditingIndex = index;
        _currentFilter = _wordControllers[index].text.toLowerCase();
        _updateFilteredWords();
      });
    } else if (_currentlyEditingIndex == index) {
      // Small delay to allow for suggestion tap
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!_focusNodes[index].hasFocus) {
          setState(() {
            if (_currentlyEditingIndex == index) {
              _filteredWords = [];
              _currentFilter = '';
              _currentlyEditingIndex = -1;
            }
          });
        }
      });
    }
  }

  /// Handle pasted text with multiple words
  void _handlePastedText(String pastedText, {int startIndex = 0}) {
    final words = pastedText.trim().split(RegExp(r'\s+'));
    
    if (words.length >= 12) {
      // Fill all 12 fields from the beginning
      for (int i = 0; i < 12; i++) {
        _wordControllers[i].text = words[i];
      }
      // Remove focus from all fields
      FocusScope.of(context).unfocus();
    } else {
      // Fill available words starting from startIndex
      for (int i = 0; i < words.length && (startIndex + i) < 12; i++) {
        _wordControllers[startIndex + i].text = words[i];
      }
      // Focus on next empty field
      final nextIndex = startIndex + words.length;
      if (nextIndex < 12) {
        _focusNodes[nextIndex].requestFocus();
      } else {
        FocusScope.of(context).unfocus();
      }
    }
    setState(() {
      // Reset visibility to hidden when pasting
      _wordVisibility = List.filled(12, false);
      _allWordsVisible = false;
      // Reset and validate all words
      _wordValidation = List.filled(12, true);
      _validateAllWords();
    });
  }



  /// Set seed phrase from external sources (QR, etc.)
  void _setSeedPhrase(String seedPhrase) {
    final words = seedPhrase.trim().split(RegExp(r'\s+'));
    
    for (int i = 0; i < 12; i++) {
      _wordControllers[i].text = i < words.length ? words[i] : '';
    }
    setState(() {
      // Reset visibility to hidden when setting new phrase
      _wordVisibility = List.filled(12, false);
      _allWordsVisible = false;
      // Reset and validate all words
      _wordValidation = List.filled(12, true);
      _validateAllWords();
    });
  }

  /// Get combined seed phrase from all fields
  String _getCombinedSeedPhrase() {
    return _wordControllers
        .map((controller) => controller.text.trim())
        .where((word) => word.isNotEmpty)
        .join(' ');
  }

  /// Check if all 12 words are filled
  bool _isValidSeedPhrase() {
    return _wordControllers.every((controller) => controller.text.trim().isNotEmpty);
  }

  /// Validate a single word against BIP39 wordlist
  bool _isValidBIP39Word(String word) {
    if (word.trim().isEmpty) return true; // Empty is valid (not filled yet)
    
    final cleanWord = word.trim().toLowerCase();
    
    // Check if contains only alphabetic characters
    if (!RegExp(r'^[a-zA-Z]+$').hasMatch(cleanWord)) {
      return false;
    }
    
    // Check if word exists in BIP39 wordlist
    return _bip39Words.contains(cleanWord);
  }

  /// Validate all words and update validation state
  void _validateAllWords() {
    bool hasErrors = false;
    
    for (int i = 0; i < 12; i++) {
      final word = _wordControllers[i].text.trim();
      final isValid = _isValidBIP39Word(word);
      _wordValidation[i] = isValid;
      
      if (!isValid && word.isNotEmpty) {
        hasErrors = true;
      }
    }
    
    _hasValidationErrors = hasErrors;
  }

  /// Check if seed phrase is complete and valid
  bool _isCompleteAndValidSeedPhrase() {
    _validateAllWords();
    return _isValidSeedPhrase() && !_hasValidationErrors;
  }

  /// Clear all word fields
  void _clearAllFields() {
    for (final controller in _wordControllers) {
      controller.clear();
    }
    setState(() {
      _filteredWords = [];
      _currentFilter = '';
      _currentlyEditingIndex = -1;
      _wordVisibility = List.filled(12, false); // Reset visibility to hidden
      _allWordsVisible = false;
      _wordValidation = List.filled(12, true); // Reset validation
      _hasValidationErrors = false;
    });
    _focusNodes[0].requestFocus();
  }

  /// Check if any field has text
  bool _hasAnyText() {
    return _wordControllers.any((controller) => controller.text.trim().isNotEmpty);
  }

  /// Toggle visibility for all words
  void _toggleAllWordsVisibility() {
    setState(() {
      _allWordsVisible = !_allWordsVisible;
      for (int i = 0; i < 12; i++) {
        _wordVisibility[i] = _allWordsVisible;
      }
    });
  }

  /// Toggle visibility for a specific word
  void _toggleWordVisibility(int index) {
    setState(() {
      _wordVisibility[index] = !_wordVisibility[index];
      
      // Update _allWordsVisible based on individual states
      _allWordsVisible = _wordVisibility.every((visible) => visible);
    });
  }

  /// Get status message based on current state
  String _getStatusMessage() {
    _validateAllWords(); // Ensure validation is up to date
    
    if (_hasValidationErrors) {
      return _safeTranslate('invalid_words_detected', 'Invalid words detected. Please check red fields.');
    } else if (_isValidSeedPhrase()) {
      return _safeTranslate('all words entered', 'All 12 words entered ✓');
    } else {
      return _safeTranslate('enter words instruction', 'Enter each word or paste all 12 words');
    }
  }

  /// Get status color based on current state
  Color _getStatusColor() {
    _validateAllWords(); // Ensure validation is up to date
    
    if (_hasValidationErrors) {
      return Colors.red;
    } else if (_isValidSeedPhrase()) {
      return const Color(0xFF03ac0e);
    } else {
      return Colors.grey;
    }
  }

  // Removed _suggestNextImportedWalletName as per edit hint

  /// Normalize mnemonic for comparison
  String _normalizeMnemonic(String mnemonic) {
    return mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Check if mnemonic already exists in any wallet
  Future<bool> _checkMnemonicExists(String mnemonic) async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      
      for (final wallet in wallets) {
        final walletName = wallet['walletName'] ?? wallet['name'] ?? '';
        final userId = wallet['userID'] ?? wallet['userId'] ?? '';
        
        if (walletName.isNotEmpty) {
          // Try to get mnemonic for this wallet (check both with and without userId)
          String? existingMnemonic;
          
          if (userId.isNotEmpty) {
            existingMnemonic = await SecureStorage.instance.getMnemonic(walletName, userId);
          } else {
            // For wallets without userId, try with empty string
            existingMnemonic = await SecureStorage.instance.getMnemonic(walletName, '');
          }
          
          if (existingMnemonic != null && _normalizeMnemonic(existingMnemonic) == _normalizeMnemonic(mnemonic)) {
            print('🔍 Mnemonic already exists in wallet: $walletName (userId: $userId)');
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking mnemonic existence: $e');
      return false;
    }
  }

  void _importWallet() async {
    if (!_isValidSeedPhrase()) return;

    final phrase = _getCombinedSeedPhrase();
    
    // Check if mnemonic already exists before making API call
    print('🔍 Checking if mnemonic already exists...');
    final mnemonicExists = await _checkMnemonicExists(phrase);
    
    if (mnemonicExists) {
      print('⚠️ Mnemonic already exists, showing error modal');
      setState(() {
        _isLoading = false;
        _showErrorModal = true;
        _errorMessage = 'This wallet has already been imported. Please use a different seed phrase.';
      });
      return;
    }
    
    print('✅ Mnemonic check passed, proceeding with import...');

    setState(() => _isLoading = true);

    // Always fetch the latest wallet list from SecureStorage
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^Imported wallet (\d+) ?$');
    for (final w in wallets) {
      final name = w['walletName'] ?? w['name'] ?? '';
      final match = regex.firstMatch(name);
      if (match != null) {
        final num = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (num > maxNum) maxNum = num;
      }
    }
    String newWalletName;
    // Ensure uniqueness in case of duplicate names
    do {
      newWalletName = 'Imported wallet ${++maxNum}';
    } while (wallets.any((w) => (w['walletName'] ?? w['name'] ?? '') == newWalletName));

    print('🚀 Starting wallet import process...');
    print('📝 Seed phrase length: ${phrase.length}');
    
    late final dynamic response; // تعریف response خارج از try-catch
    
    try {
      final mnemonic = phrase; // Use phrase variable defined earlier
      
      final imported = await WalletRepository.instance.importWallet(
        walletName: newWalletName,
        mnemonic: mnemonic,
      );
      response = LocalImportAdapter.toImportResponse(imported);
      
      print('📥 API Response received:');
      print('   Status: ${response.status}');
      print('   Message: ${response.message}');
      print('   Has Data: ${response.data != null}');
      print('   Full Response: $response');
      print('   Response Type: ${response.runtimeType}');
      
      // Log detailed server response
      print('🌐 SERVER RESPONSE DETAILS:');
      print('   📊 Status: ${response.status}');
      print('   💬 Message: ${response.message}');
      print('   📦 Has Data: ${response.data != null}');
      
      if (response.data != null) {
        print('   👤 UserID from server: ${response.data!.userID}');
        print('   🆔 WalletID from server: ${response.data!.walletID}');
        print('   📝 Mnemonic from server: ${response.data!.mnemonic != null ? "RECEIVED" : "NOT RECEIVED"}');
        print('   🏠 Addresses count: ${response.data!.addresses.length}');
        
        // Log addresses received from server
        print('   🏠 ADDRESSES FROM SERVER:');
        for (int i = 0; i < response.data!.addresses.length; i++) {
          final address = response.data!.addresses[i];
          print('     ${i + 1}. ${address.blockchainName}: ${address.publicAddress}');
        }
      }
      
      // Save response to a file for debugging
      try {
        final responseJson = response.toJson();
        print('💾 Response JSON: $responseJson');
      } catch (e) {
        print('❌ Error converting response to JSON: $e');
      }
      
      if (response.data != null) {
        print('📊 Wallet Data Details:');
        print('   UserID: ${response.data!.userID}');
        print('   WalletID: ${response.data!.walletID}');
        print('   Has Mnemonic: ${response.data!.mnemonic != null}');
        print('   Mnemonic Length: ${response.data!.mnemonic?.length ?? 0}');
      }
      
      if (response.status == 'success' && response.data != null) {
        final walletData = response.data!;
        
        print('✅ SUCCESS PATH ENTERED - Saving wallet info...');
        print('   UserID to save: ${walletData.userID}');
        print('   WalletID to save: ${walletData.walletID}');
        print('   Wallet name: $newWalletName');
        
        // Save wallet information securely
        await WalletStateManager.instance.saveWalletInfo(
          walletName: newWalletName,
          userId: walletData.userID ?? '',
          walletId: walletData.walletID ?? '',
          mnemonic: walletData.mnemonic ?? mnemonic, // مطمئن می‌شویم که mnemonic ذخیره شود
          activeTokens: ['BTC', 'ETH', 'TRX'], // ✅ Default active tokens for imported wallet
        );
        if (walletData.walletID != null && walletData.walletID!.isNotEmpty) {
          await SecureStorage.instance.saveWalletIdForWallet(newWalletName, walletData.walletID!);
        }
        
        // **اطمینان از ذخیره mnemonic**: در صورت عدم ذخیره، مستقیماً ذخیره می‌کنیم
        if (walletData.userID != null && (walletData.mnemonic != null || mnemonic.isNotEmpty)) {
          final mnemonicToSave = walletData.mnemonic ?? mnemonic;
          await SecureStorage.instance.saveMnemonic(newWalletName, walletData.userID!, mnemonicToSave);
          print('✅ Mnemonic saved in SecureStorage with key: Mnemonic_${walletData.userID!}_$newWalletName');
        }
        final debugWallets = await SecureStorage.instance.getWalletsList();
        print('Wallets after add: $debugWallets');
        
        print('💾 Wallet info saved successfully');

        // Refresh AppProvider wallets list
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        await appProvider.refreshWallets();
        
        // مطابق گزارش Kotlin: فراخوانی API balance فقط یک بار بعد از import wallet
        print('💰 Getting user balance for imported wallet (ONE TIME as per Kotlin report)...');
        try {
          final tokenProvider = appProvider.tokenProvider;
          if (tokenProvider != null) {
            print('🔄 Calling balance API once after wallet import...');
            final balances = await tokenProvider.fetchBalancesForActiveTokens();
            print('✅ Balance fetch completed after wallet import');
            print('🔍 ImportWallet DEBUG: Fetched balances: $balances');
            
            // Debug: نمایش موجودی‌های فعلی در TokenProvider بعد از fetch
            final enabledTokens = tokenProvider.enabledTokens;
            print('🔍 ImportWallet DEBUG: Current enabled tokens with balances after fetch:');
            for (final token in enabledTokens) {
              print('   - ${token.symbol}: ${token.amount ?? 0.0}');
            }
          }
        } catch (e) {
          print('⚠️ Error getting balance (continuing anyway): $e');
          // Continue with import process even if balance retrieval fails
        }
        
        print('🔄 Wallet import successful');
        print('💫 ABOUT TO START NAVIGATION PROCESS...');
        
        // Show success message with server data
        if (mounted) {
          // Remove success message - wallet imported silently
        }
        
        // Update app provider with new wallet info
        if (mounted) {
          await appProvider.setCurrentWallet(newWalletName);
          
          // بروزرسانی TokenProvider با userId جدید through AppProvider
          final tokenProvider = appProvider.tokenProvider;
          if (tokenProvider != null) {
            final userIdToUpdate = walletData.userID ?? '';
            print('🔄 Updating TokenProvider with userId: $userIdToUpdate');
            tokenProvider.updateUserId(userIdToUpdate);
          } else {
            print('⚠️ TokenProvider is null in AppProvider');
          }
        }
        
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        
        if (mounted) {
          print('🎯 Navigating to passcode screen...');
          // بررسی فعال بودن passcode
          final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
          print('🔐 Passcode enabled: $isPasscodeEnabled');
          
          await goThroughOnboardingFlow(
            context: context,
            isFromWalletCreation: false,
            isPasscodeEnabled: isPasscodeEnabled,
            walletName: newWalletName,
            mnemonic: walletData.mnemonic ?? mnemonic,
            userId: walletData.userID ?? '',
            walletId: walletData.walletID ?? '',
          );
        }
      } else if (response.status != 'success') {
        print('❌ API returned non-success status');
        print('   Status: ${response.status}');
        print('   Message: ${response.message}');
        // فقط اگر واقعا خطا بود
        throw Exception(response.message ?? 'Import failed');
      } else {
        print('⚠️ Response status is success but no data received');
        print('   Status: ${response.status}');
        print('   Has Data: ${response.data != null}');
      }
    } catch (e) {
      final errorMsg = e.toString();
      print('💥 Exception caught: $errorMsg');
      
      if (errorMsg.contains('successfully imported')) {
        print('🔄 Fallback path - Wallet imported but no data received');
        final mnemonic = phrase; // Use phrase variable defined earlier
        
        // بررسی اینکه آیا response تعریف شده و دارای data است یا نه
        try {
          if (response.data != null) {
            print('✅ Response data exists in fallback, using actual UserID');
            final walletData = response.data!;
            
            // Save wallet information securely with actual data
            await WalletStateManager.instance.saveWalletInfo(
              walletName: newWalletName,
              userId: walletData.userID ?? '',
              walletId: walletData.walletID ?? '',
              mnemonic: walletData.mnemonic ?? mnemonic,
              activeTokens: ['BTC', 'ETH', 'TRX'], // ✅ Default active tokens for imported wallet
            );
            
            print('✅ Fallback: Saved wallet with actual UserID: ${walletData.userID}');
            
            // اطمینان از ذخیره mnemonic با UserID واقعی
            if (walletData.userID != null && (walletData.mnemonic != null || mnemonic.isNotEmpty)) {
              final mnemonicToSave = walletData.mnemonic ?? mnemonic;
              await SecureStorage.instance.saveMnemonic(newWalletName, walletData.userID!, mnemonicToSave);
              print('✅ Mnemonic saved in SecureStorage (fallback) with key: Mnemonic_${walletData.userID!}_$newWalletName');
            }
          } else {
            print('⚠️ No response data in fallback, using empty UserID');
            
            await WalletStateManager.instance.saveWalletInfo(
              walletName: newWalletName,
              userId: '',
              walletId: '',
              mnemonic: mnemonic,
              activeTokens: ['BTC', 'ETH', 'TRX'], // ✅ Default active tokens for imported wallet
            );
            
            // اطمینان از ذخیره mnemonic در fallback path
            if (mnemonic.isNotEmpty) {
              await SecureStorage.instance.saveMnemonic(newWalletName, '', mnemonic);
              print('✅ Mnemonic saved in SecureStorage (fallback) with key: Mnemonic__$newWalletName');
            }
          }
        } catch (responseError) {
          print('⚠️ Error accessing response in fallback: $responseError');
          print('⚠️ Using empty UserID as fallback');
          
          await WalletStateManager.instance.saveWalletInfo(
            walletName: newWalletName,
            userId: '',
            walletId: '',
            mnemonic: mnemonic,
            activeTokens: ['BTC', 'ETH', 'TRX'], // ✅ Default active tokens for imported wallet
          );
          
          // اطمینان از ذخیره mnemonic در fallback path
          if (mnemonic.isNotEmpty) {
            await SecureStorage.instance.saveMnemonic(newWalletName, '', mnemonic);
            print('✅ Mnemonic saved in SecureStorage (fallback) with key: Mnemonic__$newWalletName');
          }
        }
        if (mounted) {
          final fallbackAppProvider = Provider.of<AppProvider>(context, listen: false);
          await fallbackAppProvider.setCurrentWallet(newWalletName);
          
          // بروزرسانی TokenProvider با userId صحیح through AppProvider
          final tokenProvider = fallbackAppProvider.tokenProvider;
          if (tokenProvider != null) {
            try {
              if (response.data != null) {
                final userIdToUpdate = response.data!.userID ?? '';
                print('🔄 Updating TokenProvider with userId (fallback): $userIdToUpdate');
                tokenProvider.updateUserId(userIdToUpdate);
              }
            } catch (responseError) {
              print('⚠️ Error accessing response for TokenProvider update: $responseError');
            }
          } else {
            print('⚠️ TokenProvider is null in AppProvider (fallback)');
          }
        }
        
        if (mounted) {
          setState(() {
            _isLoading = false;
            _showErrorModal = false;
          });
        }
        
        if (mounted) {
          print('🎯 Navigating after import (fallback path)...');
          String userIdForBackup = '';
          String walletIdForBackup = '';
          String mnemonicForBackup = phrase;
          try {
            userIdForBackup = response.data?.userID ?? '';
            walletIdForBackup = response.data?.walletID ?? '';
            mnemonicForBackup = response.data?.mnemonic ?? phrase;
          } catch (responseError) {
            print('⚠️ Error accessing response for backup navigation: $responseError');
          }
          final isPasscodeEnabled =
              await _securityManager.isPasscodeEnabled();
          await goThroughOnboardingFlow(
            context: context,
            isFromWalletCreation: false,
            isPasscodeEnabled: isPasscodeEnabled,
            walletName: newWalletName,
            mnemonic: mnemonicForBackup,
            userId: userIdForBackup,
            walletId: walletIdForBackup,
          );
        }
      } else {
        print('❌ Error path - Showing error modal');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _showErrorModal = true;
            _errorMessage = '${_safeTranslate('error_importing_wallet', 'Error importing wallet')}: ${e.toString()}';
          });
        }
      }
    }
  }

  /// Build word suggestions bar
  Widget _buildSuggestionsBar() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _filteredWords.length,
        itemBuilder: (context, index) {
          final word = _filteredWords[index];
          return GestureDetector(
            onTap: () => _selectSuggestedWord(word),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF03ac0e).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF03ac0e).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  word,
                  style: const TextStyle(
                    color: Color(0xFF03ac0e),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build the 12-word seed phrase grid
  Widget _buildSeedPhraseGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 3.5,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        return _buildWordField(index);
      },
    );
  }

  /// Build individual word input field
  Widget _buildWordField(int index) {
    final wordNumber = index + 1;
    final hasText = _wordControllers[index].text.trim().isNotEmpty;
    final isVisible = _wordVisibility[index];
    final isValid = _wordValidation[index];
    
    // Determine border color based on validation state
    Color borderColor;
    if (!isValid && hasText) {
      borderColor = Colors.red; // Invalid word
    } else if (hasText && isValid) {
      borderColor = const Color(0xFF03ac0e); // Valid word
    } else {
      borderColor = Colors.grey.withOpacity(0.3); // Empty field
    }
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: hasText ? 1.5 : 1,
        ),
        color: Colors.white,
      ),
      child: Row(
        children: [
          // Word number
          Container(
            width: 28,
            height: double.infinity,
            decoration: BoxDecoration(
              color: !isValid && hasText
                ? Colors.red.withOpacity(0.1)
                : hasText 
                  ? const Color(0xFF03ac0e).withOpacity(0.1) 
                  : Colors.grey.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                bottomLeft: Radius.circular(7),
              ),
            ),
            child: Center(
              child: Text(
                '$wordNumber',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: !isValid && hasText
                    ? Colors.red
                    : hasText 
                      ? const Color(0xFF03ac0e) 
                      : Colors.grey,
                ),
              ),
            ),
          ),
          
          // Text input
          Expanded(
            child: TextField(
              controller: _wordControllers[index],
              focusNode: _focusNodes[index],
              obscureText: !isVisible && hasText, // Hide text if not visible and has content
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                isDense: true,
                hintText: 'Word $wordNumber',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.withOpacity(0.6),
                ),
                errorText: !isValid && hasText ? 'Invalid word' : null,
                errorStyle: const TextStyle(fontSize: 8, height: 0.5),
              ),
              style: const TextStyle(fontSize: 13),
              textInputAction: index < 11 ? TextInputAction.next : TextInputAction.done,
              onSubmitted: (_) {
                if (index < 11) {
                  _focusNodes[index + 1].requestFocus();
                } else {
                  FocusScope.of(context).unfocus();
                }
              },
              onTap: () {
                // If user taps on first field and it's empty, allow paste detection
                if (index == 0 && _wordControllers[index].text.isEmpty) {
                  // This will be handled by the onChanged listener
                }
              },
            ),
          ),
          
          // Individual eye icon for each field
          if (hasText)
            GestureDetector(
              onTap: () => _toggleWordVisibility(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isVisible ? Icons.visibility_off : Icons.visibility,
                  size: 16,
                  color: isVisible ? Colors.grey : const Color(0xFF03ac0e),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _launchTerms() async {
    const url = 'https://coinceeper.com/terms-of-service';
    // URL launching functionality removed for now
    print('URL launch functionality removed');
  }

  @override
  Widget build(BuildContext context) {
    final isValid = _isCompleteAndValidSeedPhrase();
    return WillPopScope(
      onWillPop: () async {
        // Check if wallets exist, if so, don't allow back navigation
        try {
          final wallets = await SecureStorage.instance.getWalletsList();
          if (wallets.isNotEmpty) {
            print('🚫 Back navigation blocked - wallet exists');
            return false;
          }
        } catch (e) {
          print('❌ Error checking wallets for back navigation: $e');
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_safeTranslate('import_wallet', 'Import Wallet')),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        backgroundColor: Colors.white,
        body: GestureDetector(
          onTap: () {
            // Close keyboard and clear suggestions when tapping outside
            FocusScope.of(context).unfocus();
            setState(() {
              _filteredWords = [];
              _currentFilter = '';
              _currentlyEditingIndex = -1;
            });
          },
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title with Eye and QR buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _safeTranslate('import_wallet', 'Import Wallet'),
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.left,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _safeTranslate('enter 12 word phrase', 'Enter your 12 word recovery phrase'),
                                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                                      textAlign: TextAlign.left,
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Eye icon for visibility toggle
                                  IconButton(
                                    onPressed: _toggleAllWordsVisibility,
                                    icon: Icon(
                                      _allWordsVisible ? Icons.visibility_off : Icons.visibility,
                                      size: 24,
                                    ),
                                    color: _allWordsVisible ? Colors.grey : const Color(0xFF03ac0e),
                                    style: IconButton.styleFrom(
                                      backgroundColor: _allWordsVisible 
                                        ? Colors.grey.withOpacity(0.1)
                                        : const Color(0xFF03ac0e).withOpacity(0.1),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // QR code scanner
                                  IconButton(
                                    onPressed: () async {
                                      FocusScope.of(context).unfocus(); // Close keyboard
                                      final result = await AppNavigation.pushNamed(
                                        context, 
                                        '/qr-scanner',
                                        arguments: {'returnScreen': 'import_wallet'},
                                      );
                                      if (result != null && result is String && result.isNotEmpty) {
                                        _setSeedPhrase(result);
                                      }
                                    },
                                    icon: const Icon(Icons.qr_code, size: 28),
                                    color: const Color(0xFF03ac0e),
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFF03ac0e).withOpacity(0.1),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          // 12-word grid
                          _buildSeedPhraseGrid(),
                          
                          const SizedBox(height: 16),
                          
                          // Clear All button
                          Center(
                            child: TextButton.icon(
                              onPressed: _hasAnyText() ? _clearAllFields : null,
                              icon: Icon(
                                Icons.clear_all, 
                                size: 18,
                                color: _hasAnyText() ? Colors.red : Colors.grey,
                              ),
                              label: Text(
                                _safeTranslate('clear_all', 'Clear All'),
                                style: TextStyle(
                                  color: _hasAnyText() ? Colors.red : Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Status indicator
                          Center(
                            child: Text(
                              _getStatusMessage(),
                              style: TextStyle(
                                color: _getStatusColor(),
                                fontSize: 14,
                                fontWeight: isValid ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Word suggestions bar above keyboard
                if (_filteredWords.isNotEmpty)
                  _buildSuggestionsBar(),
                
                // Terms and conditions
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(
                        _safeTranslate('by_continuing_agree', 'By continuing, you agree to the '),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      GestureDetector(
                        onTap: _launchTerms,
                        child: Text(
                          _safeTranslate('terms_and_conditions', 'Terms and Conditions'),
                          style: const TextStyle(
                            color: Color(0xFF03ac0e),
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                
                // Import button
                Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, bottom: 32, top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isValid && !_isLoading ? _importWallet : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isValid ? const Color(0xFF37b3f7) : const Color(0xFF858585),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              _safeTranslate('import', 'Import'),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ),
                
                // Error modal
                if (_showErrorModal)
                  _ErrorModal(
                    message: _errorMessage,
                    onDismiss: () => setState(() => _showErrorModal = false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorModal extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorModal({required this.message, required this.onDismiss});

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Color(0xFFFF1961), size: 48),
                const SizedBox(height: 16),
                Text(
                  _safeTranslate(context, 'error', 'Error'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF1961),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: Text(_safeTranslate(context, 'ok', 'OK'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 